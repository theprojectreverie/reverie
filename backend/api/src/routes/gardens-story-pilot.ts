import type {FastifyPluginAsync} from "fastify";
import {z} from "zod";
import {actionSchema,startStoryBattle,actStoryBattle,resumeStoryBattle,abandonStoryBattle,storyTransactionAdmission} from "../world/story-combat-service.js";
import {gardenEncounterIds,isGardenEncounter,verifyStoryEncounter} from "../world/story-encounter-admission.js";
import {readVerifiedOpeningProgress} from "../world/story-progression-proof.js";
import {readElathraAudience,advanceElathraAudience} from "../world/story-elathra.js";
type Outcome={ok:true;[key:string]:unknown}|{ok:false;reason:string};
type Claims={sub?:string;playerId?:string;tokenVersion?:number};
const group=z.string().refine(isGardenEncounter);
const schema=z.discriminatedUnion("operation",[
 z.object({operation:z.literal("status")}).strict(),
 z.object({operation:z.literal("audience"),choice:z.enum(["hear","accept"])}).strict(),
 z.object({operation:z.literal("start"),groupId:group}).strict(),
 z.object({operation:z.literal("act"),groupId:group,battleId:z.string().uuid(),sequence:z.number().int().min(1).max(256),action:actionSchema}).strict(),
 z.object({operation:z.literal("resume"),groupId:group,battleId:z.string().uuid()}).strict(),
 z.object({operation:z.literal("abandon"),groupId:group,battleId:z.string().uuid()}).strict()
]);
// Nonproduction only. Do not enable live until full movement authority and client routing are ready.
export const gardensStoryPilotRoutes:FastifyPluginAsync=async app=>{
 app.post("/",{config:{rateLimit:{max:90,timeWindow:"1 minute"}}},async(req,reply)=>{
  reply.header("Cache-Control","no-store");
  let c:Claims;try{await req.jwtVerify();c=req.user as Claims;}catch{return reply.code(401).send({ok:false,reason:"authentication_required"});}
  if(!c.sub||!c.playerId||!Number.isInteger(c.tokenVersion))return reply.code(401).send({ok:false,reason:"authentication_required"});
  const parsed=schema.safeParse(req.body);if(!parsed.success)return reply.code(400).send({ok:false,reason:"invalid_action"});
  const id=c.playerId,op=parsed.data;
  const result=await storyTransactionAdmission.run<Outcome>(id,async db=>{
   const identity=await db.query("SELECT p.id FROM players p JOIN accounts a ON a.id=p.account_id WHERE p.id=$1 AND a.id=$2 AND a.status='active' AND a.token_version=$3 FOR UPDATE OF p",[id,c.sub,c.tokenVersion]);
   if(!identity.rowCount)return {ok:false,reason:"authentication_required"};
   if(op.operation==="status"){
    if(!(await readVerifiedOpeningProgress(db,id)).geraldDefeated)return {ok:false,reason:"story_progression_required"};
    const rows=(await db.query<{group_id:string;remaining_ms:number}>(`SELECT group_id,GREATEST(0,CEIL(EXTRACT(EPOCH FROM (MAX(settled_at)+interval '15 seconds'-clock_timestamp()))*1000))::int AS remaining_ms FROM story_battle_sessions WHERE player_id=$1 AND group_id=ANY($2::text[]) AND status='victory' AND settled_at>clock_timestamp()-interval '15 seconds' GROUP BY group_id`,[id,gardenEncounterIds])).rows;
    const active=(await db.query<{id:string;group_id:string}>("SELECT id,group_id FROM story_battle_sessions WHERE player_id=$1 AND status='active' AND group_id=ANY($2::text[]) LIMIT 1",[id,gardenEncounterIds])).rows[0];
    return {ok:true,audience:await readElathraAudience(db,id),encounters:gardenEncounterIds.map(groupId=>({groupId,remainingMs:rows.find(r=>r.group_id===groupId)?.remaining_ms??0})),active:active?{battleId:active.id,groupId:active.group_id}:null};
   }
   if(op.operation==="audience")return advanceElathraAudience(db,id,op.choice);
   if(op.operation==="start"){
    const active=(await db.query<{id:string}>("SELECT id FROM story_battle_sessions WHERE player_id=$1 AND group_id=$2 AND status='active' LIMIT 1",[id,op.groupId])).rows[0];
    if(active)return resumeStoryBattle(db,id,active.id);
    const allowed=await verifyStoryEncounter(db,id,op.groupId);if(!allowed.ok)return allowed;
    return startStoryBattle(db,id,op.groupId);
   }
   if(!(await db.query("SELECT 1 FROM story_battle_sessions WHERE id=$1 AND player_id=$2 AND group_id=$3",[op.battleId,id,op.groupId])).rowCount)return {ok:false,reason:"battle_not_found"};
   if(op.operation==="resume")return resumeStoryBattle(db,id,op.battleId);
   if(op.operation==="abandon")return abandonStoryBattle(db,id,op.battleId);
   return actStoryBattle(db,id,op.battleId,op.sequence,op.action);
  });
  if(!result.ok)return reply.code(result.reason==="authentication_required"?401:result.reason==="battle_not_found"?404:result.reason.startsWith("story_worker")||result.reason.endsWith("_busy")?503:409).send(result);
  return {...result,playerId:id};
 });
};
