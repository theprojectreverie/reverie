import type {FastifyPluginAsync,FastifyRequest,FastifyReply} from "fastify";
import {pool} from "../db.js";
import {expirePlayerMatches} from "../world/pvp-expiry.js";
import {resolvePvpAction,type PvpState,type PvpSkill} from "../world/pvp.js";
import {validatePersistedPvpState,sequencePvpEvents} from "../world/pvp-runtime.js";
import {isReplayCursorValid} from "../world/event-cursor.js";

type Claims={playerId?:string;sub?:string;tokenVersion?:number};
type StoredState=PvpState & {skillbook?:Record<string,PvpSkill>};
async function authenticatedPlayer(req:FastifyRequest,reply:FastifyReply):Promise<string|null>{
 try{
  await req.jwtVerify();
  const claims=req.user as Claims;
  if(claims.playerId&&claims.sub&&Number.isInteger(claims.tokenVersion)){
   const current=await pool.query<{token_version:number;status:string}>("SELECT a.token_version,a.status FROM accounts a JOIN players p ON p.account_id=a.id WHERE a.id=$1 AND p.id=$2",[claims.sub,claims.playerId]);
   if(current.rows[0]?.status==="active"&&current.rows[0].token_version===claims.tokenVersion)return claims.playerId;
  }
 }catch{/* unauthorized */}
 reply.code(401).send({error:"authentication_required"});return null;
}
const uuid=/^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;
function publicState(state:PvpState){
 return {matchId:state.matchId,sequence:state.sequence,turn:state.turn,turnPlayerId:state.turnPlayerId,status:state.status,winnerId:state.winnerId??null,units:state.units,bonds:state.bonds??{}};
}
async function isParticipant(matchId:string,playerId:string){
 return pool.query("SELECT 1 FROM pvp_match_players WHERE match_id=$1 AND player_id=$2",[matchId,playerId]);
}

export const pvpMatchRoutes:FastifyPluginAsync=async app=>{
 app.post("/:matchId/action",{config:{rateLimit:{max:60,timeWindow:"1 minute"}},schema:{
  params:{type:"object",required:["matchId"],properties:{matchId:{type:"string",pattern:uuid.source}}},
  body:{type:"object",additionalProperties:false,required:["actorUid","skillId","targetUids","sequence"],properties:{
   actorUid:{type:"string",minLength:1,maxLength:100},skillId:{type:"string",minLength:1,maxLength:100},
   targetUids:{type:"array",maxItems:4,items:{type:"string",minLength:1,maxLength:100}},
   sequence:{type:"integer",minimum:1,maximum:Number.MAX_SAFE_INTEGER}
  }}
 }},async(req,reply)=>{
  const playerId=await authenticatedPlayer(req,reply);if(!playerId)return;
  const {matchId}=req.params as {matchId:string};
  const body=req.body as {actorUid:string;skillId:string;targetUids:string[];sequence:number};
  const client=await pool.connect();
  try{
   await client.query("BEGIN");
   const match=await client.query<{status:string;state:StoredState|null;state_sequence:string;next_event_sequence:string;expires_at:Date|null}>(
    "SELECT m.status,m.state,m.state_sequence::text,m.next_event_sequence::text,m.expires_at FROM pvp_matches m JOIN pvp_match_players mp ON mp.match_id=m.id WHERE m.id=$1 AND mp.player_id=$2 FOR UPDATE OF m",[matchId,playerId]);
   const row=match.rows[0];
   if(!row){await client.query("ROLLBACK");return reply.code(404).send({error:"match_not_found"});}
   if(row.status!=="active"||!row.state){await client.query("ROLLBACK");return reply.code(409).send({error:"match_not_active"});}
   if(row.expires_at&&row.expires_at.getTime()<=Date.now()){
    const eventSequence=Number(row.next_event_sequence);
    if(!Number.isSafeInteger(eventSequence)||eventSequence<1||eventSequence>=Number.MAX_SAFE_INTEGER){await client.query("ROLLBACK");return reply.code(500).send({error:"event_sequence_exhausted"});}
    await client.query("INSERT INTO pvp_events(match_id,sequence,actor_player_id,event) VALUES($1,$2,NULL,$3::jsonb)",
     [matchId,eventSequence,JSON.stringify({type:"match_expired",reason:"timeout"})]);
    await client.query("UPDATE pvp_matches SET status='expired',next_event_sequence=$2,completed_at=now(),expires_at=NULL,result=$3::jsonb WHERE id=$1",
     [matchId,eventSequence+1,JSON.stringify({reason:"timeout",winnerId:null})]);
    await client.query("UPDATE pvp_queue_tickets SET status='expired' WHERE match_id=$1 AND status='matched'",[matchId]);
    await client.query("COMMIT");return reply.code(410).send({error:"match_expired"});
   }
   const stored=row.state;
   if(!stored.skillbook||typeof stored.skillbook!=="object"||Array.isArray(stored.skillbook)){
    await client.query("ROLLBACK");return reply.code(500).send({error:"match_runtime_corrupt"});
   }
   const {skillbook,...stateData}=stored;
   const state=stateData as PvpState;
   if(!validatePersistedPvpState(state,matchId,Number(row.state_sequence))){
    await client.query("ROLLBACK");return reply.code(500).send({error:"match_sequence_corrupt"});
   }
   const result=resolvePvpAction(state,{playerId,actorUid:body.actorUid,skillId:body.skillId,targetUids:body.targetUids,sequence:body.sequence},skillbook);
   if(!result.ok){await client.query("ROLLBACK");return reply.code(409).send({error:result.reason,expectedSequence:state.sequence+1,turnPlayerId:state.turnPlayerId});}
   const eventBatch=sequencePvpEvents(Number(row.next_event_sequence),result.events);
   if(!eventBatch){await client.query("ROLLBACK");return reply.code(500).send({error:"event_sequence_exhausted"});}
   for(const entry of eventBatch.events){
    await client.query("INSERT INTO pvp_events(match_id,sequence,actor_player_id,event) VALUES($1,$2,$3,$4::jsonb)",
     [matchId,entry.sequence,playerId,JSON.stringify(entry.event)]);
   }
   const nextStored={...result.state,skillbook};
   await client.query(
    "UPDATE pvp_matches SET state=$2::jsonb,state_sequence=$3,next_event_sequence=$4,turn_player_id=$5,status=$6,completed_at=CASE WHEN $6='completed' THEN now() ELSE completed_at END,expires_at=CASE WHEN $6='completed' THEN NULL ELSE now()+interval '15 minutes' END,result=CASE WHEN $6='completed' THEN $7::jsonb ELSE result END WHERE id=$1",
    [matchId,JSON.stringify(nextStored),result.state.sequence,eventBatch.nextSequence,result.state.turnPlayerId,result.state.status,result.state.status==="completed"?JSON.stringify({winnerId:result.state.winnerId??null}):null]);
   if(result.state.status==="completed"){
    await client.query("UPDATE pvp_queue_tickets SET status='completed' WHERE match_id=$1 AND status='matched'",[matchId]);
   }
   await client.query("COMMIT");
   return {matchId,sequence:result.state.sequence,turn:result.state.turn,turnPlayerId:result.state.turnPlayerId,status:result.state.status,winnerId:result.state.winnerId??null,events:result.events};
  }catch(error){await client.query("ROLLBACK");req.log.error(error);return reply.code(500).send({error:"pvp_action_failed"});}
  finally{client.release();}
 });


 app.post("/:matchId/surrender",{config:{rateLimit:{max:5,timeWindow:"1 minute"}},schema:{
  params:{type:"object",required:["matchId"],properties:{matchId:{type:"string",pattern:uuid.source}}}
 }},async(req,reply)=>{
  const playerId=await authenticatedPlayer(req,reply);if(!playerId)return;
  const {matchId}=req.params as {matchId:string};
  const client=await pool.connect();
  try{
   await client.query("BEGIN");
   const match=await client.query<{status:string;state:StoredState|null;state_sequence:string;next_event_sequence:string;expires_at:Date|null}>(
    "SELECT m.status,m.state,m.state_sequence::text,m.next_event_sequence::text,m.expires_at FROM pvp_matches m JOIN pvp_match_players mp ON mp.match_id=m.id WHERE m.id=$1 AND mp.player_id=$2 FOR UPDATE OF m",[matchId,playerId]);
   const row=match.rows[0];
   if(!row){await client.query("ROLLBACK");return reply.code(404).send({error:"match_not_found"});}
   if(row.status!=="active"||!row.state){await client.query("ROLLBACK");return reply.code(409).send({error:"match_not_active"});}
   if(row.expires_at&&row.expires_at.getTime()<=Date.now()){
    const eventBatch=sequencePvpEvents(Number(row.next_event_sequence),[{type:"match_expired",reason:"timeout"}]);
    const expiredEvent=eventBatch?.events[0];
    if(!eventBatch||!expiredEvent){await client.query("ROLLBACK");return reply.code(500).send({error:"event_sequence_exhausted"});}
    await client.query("INSERT INTO pvp_events(match_id,sequence,actor_player_id,event) VALUES($1,$2,NULL,$3::jsonb)",
     [matchId,expiredEvent.sequence,JSON.stringify(expiredEvent.event)]);
    await client.query("UPDATE pvp_matches SET status='expired',next_event_sequence=$2,completed_at=now(),expires_at=NULL,result=$3::jsonb WHERE id=$1",
     [matchId,eventBatch.nextSequence,JSON.stringify({reason:"timeout",winnerId:null})]);
    await client.query("UPDATE pvp_queue_tickets SET status='expired' WHERE match_id=$1 AND status='matched'",[matchId]);
    await client.query("COMMIT");
    return reply.code(410).send({error:"match_expired"});
   }
   const stored=row.state;
   if(!validatePersistedPvpState(stored,matchId,Number(row.state_sequence))){
    await client.query("ROLLBACK");return reply.code(500).send({error:"match_sequence_corrupt"});
   }
   const opponent=await client.query<{player_id:string}>(
    "SELECT player_id FROM pvp_match_players WHERE match_id=$1 AND player_id<>$2 ORDER BY team LIMIT 1",[matchId,playerId]);
   if(!opponent.rows[0]){await client.query("ROLLBACK");return reply.code(500).send({error:"match_opponent_missing"});}
   const winnerId=opponent.rows[0].player_id;
   const nextSequence=Number(row.state_sequence)+1;
   if(!Number.isSafeInteger(nextSequence)){await client.query("ROLLBACK");return reply.code(500).send({error:"match_sequence_exhausted"});}
   const eventBatch=sequencePvpEvents(Number(row.next_event_sequence),[{type:"match_surrendered",playerId,winnerId},{type:"match_completed",winnerId,reason:"surrender"}]);
   if(!eventBatch){await client.query("ROLLBACK");return reply.code(500).send({error:"event_sequence_exhausted"});}
   for(const entry of eventBatch.events){
    await client.query("INSERT INTO pvp_events(match_id,sequence,actor_player_id,event) VALUES($1,$2,$3,$4::jsonb)",
     [matchId,entry.sequence,playerId,JSON.stringify(entry.event)]);
   }
   const completedState={...stored,status:"completed" as const,winnerId,sequence:nextSequence};
   await client.query(
    "UPDATE pvp_matches SET status='completed',state=$2::jsonb,state_sequence=$3,next_event_sequence=$4,completed_at=now(),expires_at=NULL,result=$5::jsonb WHERE id=$1",
    [matchId,JSON.stringify(completedState),nextSequence,eventBatch.nextSequence,JSON.stringify({winnerId,reason:"surrender",surrenderedBy:playerId})]);
   await client.query("UPDATE pvp_queue_tickets SET status='completed' WHERE match_id=$1 AND status='matched'",[matchId]);
   await client.query("COMMIT");
   return {matchId,status:"completed",winnerId,reason:"surrender",events:eventBatch.events};
  }catch(error){await client.query("ROLLBACK");req.log.error(error);return reply.code(500).send({error:"pvp_surrender_failed"});}
  finally{client.release();}
 });

 app.get("/:matchId/events",{config:{rateLimit:{max:120,timeWindow:"1 minute"}},schema:{
  params:{type:"object",required:["matchId"],properties:{matchId:{type:"string",pattern:uuid.source}}},
  querystring:{type:"object",properties:{after:{type:"string",pattern:"^(0|[1-9][0-9]{0,15})$"}},additionalProperties:false}
 }},async(req,reply)=>{
  const playerId=await authenticatedPlayer(req,reply);if(!playerId)return;
  const {matchId}=req.params as {matchId:string};
  const query=req.query as {after?:string};
  const after=query.after===undefined?0:Number(query.after);
  if(!Number.isSafeInteger(after)||after<0)return reply.code(400).send({error:"invalid_replay_cursor"});
  const client=await pool.connect();
  try{
   await client.query("BEGIN");
   await expirePlayerMatches(client,playerId);
   const match=await client.query<{status:string;state:StoredState|null;state_sequence:string;latest_sequence:string}>(
    "SELECT m.status,m.state,m.state_sequence::text,COALESCE((SELECT max(e.sequence)::text FROM pvp_events e WHERE e.match_id=m.id),'0') AS latest_sequence FROM pvp_matches m JOIN pvp_match_players mp ON mp.match_id=m.id WHERE m.id=$1 AND mp.player_id=$2 FOR SHARE OF m",[matchId,playerId]);
   const row=match.rows[0];
   if(!row){await client.query("ROLLBACK");return reply.code(404).send({error:"match_not_found"});}
   const latest=Number(row.latest_sequence);
   if(!isReplayCursorValid(after,latest)){await client.query("ROLLBACK");return reply.code(400).send({error:"future_replay_cursor",latestSequence:latest});}
   const events=await client.query<{sequence:string;actor_player_id:string|null;event:Record<string,unknown>}>(
    "SELECT sequence::text,actor_player_id,event FROM pvp_events WHERE match_id=$1 AND sequence>$2 ORDER BY sequence LIMIT 201",[matchId,after]);
   const more=events.rows.length>200;
   const page=more?events.rows.slice(0,200):events.rows;
   const last=page.length?Number(page[page.length-1]!.sequence):after;
   await client.query("COMMIT");
   const stored=row.state;
   let state:ReturnType<typeof publicState>|null=null;
   if(stored){const {skillbook:_privateSkills,seed:_privateSeed,passiveFlags:_privateFlags,...safe}=stored;state={...safe,status:row.status,winnerId:row.status==="expired"||row.status==="cancelled"?null:safe.winnerId??null} as ReturnType<typeof publicState>;}
   return {matchId,status:row.status,state,stateIsLatestSnapshot:state!==null,snapshotEventSequence:latest,events:page.map(e=>({sequence:Number(e.sequence),actorPlayerId:e.actor_player_id,event:e.event})),eventsAfter:after,hasMoreEvents:more,nextCursor:more?last:null,latestSequence:latest};
  }catch(error){await client.query("ROLLBACK");req.log.error(error);return reply.code(500).send({error:"pvp_replay_failed"});}
  finally{client.release();}
 });
};
