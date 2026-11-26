import type {FastifyPluginAsync} from "fastify";
import {z} from "zod";
import {actionSchema,startStoryBattle,actStoryBattle,resumeStoryBattle,abandonStoryBattle,storyTransactionAdmission} from "../world/story-combat-service.js";
import {TUTORIAL_GROUP,VILLAGE_GROUP,verifiedStoryVictories} from "../world/story-progression-proof.js";
import {openingEncounterInRange} from "../world/story-opening-geometry.js";
import type {PoolClient} from "pg";
type Outcome={ok:true;[key:string]:unknown}|{ok:false;reason:string};
type Claims={sub?:string;playerId?:string;tokenVersion?:number};
const schema=z.discriminatedUnion("operation",[
 z.object({operation:z.literal("start")}).strict(),
 z.object({operation:z.literal("act"),battleId:z.string().uuid(),sequence:z.number().int().min(1).max(256),action:actionSchema}).strict(),
 z.object({operation:z.literal("resume"),battleId:z.string().uuid()}).strict(),
 z.object({operation:z.literal("abandon"),battleId:z.string().uuid()}).strict()
]);
async function eligible(db:PoolClient,id:string):Promise<boolean>{
 const pos=(await db.query<{x:number;y:number}>(`SELECT p.x,p.y FROM game_server_player_state p JOIN game_servers s ON s.id=p.server_id JOIN game_server_players a ON a.server_id=s.id AND a.player_id=p.player_id WHERE p.player_id=$1 AND s.region_id='story_village' AND s.status='online' AND s.heartbeat_at>now()-interval '60 seconds' AND p.updated_at>now()-interval '15 seconds' AND EXISTS(SELECT 1 FROM game_server_player_connections c WHERE c.server_id=s.id AND c.player_id=p.player_id AND c.lease_expires_at>now())`,[id])).rows[0];
 return !!pos&&openingEncounterInRange("story_village",VILLAGE_GROUP,pos);
}
// Deliberately unregistered in production: dedicated movement is not yet full obstacle authority.
export const geraldStoryPilotRoutes:FastifyPluginAsync=async app=>{
 app.post("/",{config:{rateLimit:{max:60,timeWindow:"1 minute"}}},async(req,reply)=>{
  reply.header("Cache-Control","no-store");
  let c:Claims;try{await req.jwtVerify();c=req.user as Claims;}catch{return reply.code(401).send({ok:false,reason:"authentication_required"});}
  if(!c.sub||!c.playerId||!Number.isInteger(c.tokenVersion))return reply.code(401).send({ok:false,reason:"authentication_required"});
  const parsed=schema.safeParse(req.body);if(!parsed.success)return reply.code(400).send({ok:false,reason:"invalid_action"});
  const id=c.playerId,op=parsed.data;
  const result=await storyTransactionAdmission.run<Outcome>(id,async db=>{
   const identity=await db.query("SELECT p.id FROM players p JOIN accounts a ON a.id=p.account_id WHERE p.id=$1 AND a.id=$2 AND a.status='active' AND a.token_version=$3 FOR UPDATE OF p",[id,c.sub,c.tokenVersion]);
   if(!identity.rowCount)return {ok:false,reason:"authentication_required"};
   if(op.operation==="start"){
    const wins=await verifiedStoryVictories(db,id,[TUTORIAL_GROUP,VILLAGE_GROUP]);
    if(!wins.includes(TUTORIAL_GROUP))return {ok:false,reason:"story_progression_required"};
    if(wins.includes(VILLAGE_GROUP)){
     const won=(await db.query<{id:string}>("SELECT id FROM story_battle_sessions WHERE player_id=$1 AND group_id=$2 AND status='victory' AND settled_at IS NOT NULL AND state->'view'->>'status'='victory' ORDER BY finished_at DESC LIMIT 1",[id,VILLAGE_GROUP])).rows[0];
     if(won)return resumeStoryBattle(db,id,won.id);
    }
    const active=(await db.query<{id:string}>("SELECT id FROM story_battle_sessions WHERE player_id=$1 AND group_id=$2 AND status='active' AND state->'view'->>'status'='active' LIMIT 1",[id,VILLAGE_GROUP])).rows[0];
    if(active)return resumeStoryBattle(db,id,active.id);
    if(!await eligible(db,id))return {ok:false,reason:"encounter_position_required"};
    return startStoryBattle(db,id,VILLAGE_GROUP);
   }
   if(!(await db.query("SELECT 1 FROM story_battle_sessions WHERE id=$1 AND player_id=$2 AND group_id=$3",[op.battleId,id,VILLAGE_GROUP])).rowCount)return {ok:false,reason:"battle_not_found"};
   if(op.operation==="resume")return resumeStoryBattle(db,id,op.battleId);
   if(op.operation==="abandon")return abandonStoryBattle(db,id,op.battleId);
   return actStoryBattle(db,id,op.battleId,op.sequence,op.action);
  });
  if(!result.ok)return reply.code(result.reason==="authentication_required"?401:result.reason==="battle_not_found"?404:result.reason.startsWith("story_worker")||result.reason.endsWith("_busy")?503:409).send(result);
  return {...result,playerId:id};
 });
};
