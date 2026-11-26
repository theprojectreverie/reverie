import type {FastifyPluginAsync,FastifyRequest,FastifyReply} from "fastify";
import {z} from "zod";
import {actionSchema,startStoryBattle,actStoryBattle,resumeStoryBattle,abandonStoryBattle,storyTransactionAdmission} from "../world/story-combat-service.js";
import {TUTORIAL_GROUP,verifiedStoryVictories} from "../world/story-progression-proof.js";
import type {PoolClient} from "pg";
type Claims={sub?:string;playerId?:string;tokenVersion?:number};
const body=z.discriminatedUnion("operation",[
 z.object({operation:z.literal("start")}).strict(),
 z.object({operation:z.literal("act"),battleId:z.string().uuid(),sequence:z.number().int().min(1).max(256),action:actionSchema}).strict(),
 z.object({operation:z.literal("abandon"),battleId:z.string().uuid()}).strict(),
 z.object({operation:z.literal("resume"),battleId:z.string().uuid()}).strict(),
 z.object({operation:z.literal("ack_unlock"),battleId:z.string().uuid()}).strict()
]);
type Outcome={ok:true;[key:string]:unknown}|{ok:false;reason:string};
export const tutorialSparRoutes:FastifyPluginAsync=async app=>{
 app.addHook("onSend",async(_req,reply,payload)=>{reply.header("Cache-Control","no-store");return payload;});
 app.post("/",{config:{rateLimit:{max:60,timeWindow:"1 minute"}}},async(req:FastifyRequest,reply:FastifyReply)=>{
  let c:Claims;try{await req.jwtVerify();c=req.user as Claims;}catch{return reply.code(401).send({ok:false,reason:"authentication_required"});}
  if(!c.sub||!c.playerId||!Number.isInteger(c.tokenVersion))return reply.code(401).send({ok:false,reason:"authentication_required"});
  const parsed=body.safeParse(req.body);if(!parsed.success)return reply.code(400).send({ok:false,reason:"invalid_action"});
  const id=c.playerId, op=parsed.data;
  const result=await storyTransactionAdmission.run<Outcome>(id,async(db:PoolClient)=>{
   const identity=await db.query("SELECT p.id FROM players p JOIN accounts a ON a.id=p.account_id WHERE p.id=$1 AND a.id=$2 AND a.status='active' AND a.token_version=$3 FOR UPDATE OF p",[id,c.sub,c.tokenVersion]);
   if(!identity.rowCount)return {ok:false,reason:"authentication_required"};
   async function withNotice(result:Outcome):Promise<Outcome>{
    if(!result.ok)return result;
    const view=result.view as {status?:string}|undefined;
    if(view?.status!=="victory")return {...result,unlockNoticePending:false};
    const q=await db.query<{seen:boolean}>("SELECT COALESCE(settings->>'companion_menu_unlock_seen','false')='true' AS seen FROM players WHERE id=$1",[id]);
    return {...result,unlockNoticePending:q.rows[0]?.seen!==true};
   }
   if(op.operation==="start"){
    const name=await db.query("SELECT 1 FROM players WHERE id=$1 AND NULLIF(settings->>'tutorial_companion_name','') IS NOT NULL",[id]);
    if(!name.rowCount)return {ok:false,reason:"name_companion_first"};
    if((await verifiedStoryVictories(db,id,[TUTORIAL_GROUP])).includes(TUTORIAL_GROUP)){
     const won=await db.query<{id:string}>("SELECT id FROM story_battle_sessions WHERE player_id=$1 AND group_id=$2 AND status='victory' AND finished_at IS NOT NULL AND state->'view'->>'status'='victory' ORDER BY finished_at DESC LIMIT 1",[id,TUTORIAL_GROUP]);
     if(won.rows[0])return await withNotice(await resumeStoryBattle(db,id,won.rows[0].id));
    }
    return await withNotice(await startStoryBattle(db,id,TUTORIAL_GROUP));
   }
   const owned=await db.query("SELECT 1 FROM story_battle_sessions WHERE id=$1 AND player_id=$2 AND group_id=$3",[op.battleId,id,TUTORIAL_GROUP]);
   if(!owned.rowCount)return {ok:false,reason:"battle_not_found"};
   if(op.operation==="ack_unlock"){
    const won=await db.query("SELECT 1 FROM story_battle_sessions WHERE id=$1 AND player_id=$2 AND group_id=$3 AND status='victory' AND finished_at IS NOT NULL AND state->'view'->>'status'='victory'",[op.battleId,id,TUTORIAL_GROUP]);
    if(!won.rowCount)return {ok:false,reason:"victory_required"};
    await db.query("UPDATE players SET settings=jsonb_set(COALESCE(settings,'{}'::jsonb),'{companion_menu_unlock_seen}','true'::jsonb,true) WHERE id=$1",[id]);
    return {ok:true,unlockNoticePending:false};
   }
   if(op.operation==="resume")return await withNotice(await resumeStoryBattle(db,id,op.battleId));
   return op.operation==="act"?await withNotice(await actStoryBattle(db,id,op.battleId,op.sequence,op.action)):await abandonStoryBattle(db,id,op.battleId);
  });
  if(!result.ok){const status=result.reason==="authentication_required"?401:result.reason==="battle_not_found"?404:result.reason.startsWith("story_worker")||result.reason.endsWith("_busy")?503:409;return reply.code(status).send(result);}
  return {...result,playerId:id};
 });
};