import type {FastifyPluginAsync,FastifyRequest,FastifyReply} from "fastify";
import {createHash,randomBytes} from "node:crypto";
import {z} from "zod";
import {pool} from "../db.js";
import {broadcast} from "./realtime.js";
import {validateRegionProposal} from "../world/movement.js";

type Claims={playerId?:string;sub?:string;tokenVersion?:number};
async function playerFromRequest(req:FastifyRequest,reply:FastifyReply):Promise<string|null>{
 try{await req.jwtVerify();const claims=req.user as Claims;if(claims.playerId&&claims.sub&&Number.isInteger(claims.tokenVersion)){const current=await pool.query<{token_version:number;status:string}>("SELECT token_version,status FROM accounts WHERE id=$1",[claims.sub]);if(current.rows[0]?.status==="active"&&current.rows[0].token_version===claims.tokenVersion)return claims.playerId;}}
 catch{/* rejected below */}
 reply.code(401).send({error:"authentication_required"});return null;
}
const createBody=z.object({regionId:z.string().trim().min(2).max(48).regex(/^[a-z0-9_]+$/),maxMembers:z.number().int().min(2).max(4).default(4)});
const joinBody=z.object({inviteCode:z.string().min(20).max(64)});
const idParams=z.object({lobbyId:z.string().uuid()});
const digest=(value:string)=>createHash("sha256").update(value).digest("hex");
const isUniqueViolation=(error:unknown)=>typeof error==="object"&&error!==null&&"code" in error&&(error as {code?:unknown}).code==="23505";

export const coopRoutes:FastifyPluginAsync=async app=>{
 app.post("/lobbies",{config:{rateLimit:{max:8,timeWindow:"1 minute"}}},async(req,reply)=>{
  const playerId=await playerFromRequest(req,reply);if(!playerId)return;
  const parsed=createBody.safeParse(req.body);if(!parsed.success)return reply.code(400).send({error:"invalid_lobby_settings"});if(!validateRegionProposal(parsed.data.regionId,parsed.data.regionId))return reply.code(400).send({error:"unknown_region"});
  const inviteCode=randomBytes(18).toString("base64url");const client=await pool.connect();
  try{
   await client.query("BEGIN");
   const existing=await client.query("SELECT lobby_id FROM co_op_lobby_members WHERE player_id=$1 FOR UPDATE",[playerId]);
   if(existing.rowCount){await client.query("ROLLBACK");return reply.code(409).send({error:"already_in_lobby"});}
   const created=await client.query<{id:string}>(
    "INSERT INTO co_op_lobbies(leader_player_id,region_id,max_members,invite_code_hash) VALUES($1,$2,$3,$4) RETURNING id",
    [playerId,parsed.data.regionId,parsed.data.maxMembers,digest(inviteCode)]);
   const lobbyId=created.rows[0]!.id;
   await client.query("INSERT INTO co_op_lobby_members(lobby_id,player_id,role) VALUES($1,$2,'leader')",[lobbyId,playerId]);
   await client.query("INSERT INTO player_presence(player_id,state,region_id,last_heartbeat_at) VALUES($1,'in_lobby',$2,now()) ON CONFLICT(player_id) DO UPDATE SET state='in_lobby',region_id=EXCLUDED.region_id,last_heartbeat_at=now(),updated_at=now()",[playerId,parsed.data.regionId]);
   await client.query("COMMIT");
   return reply.code(201).send({lobbyId,regionId:parsed.data.regionId,maxMembers:parsed.data.maxMembers,inviteCode});
  }catch(e){await client.query("ROLLBACK");if(isUniqueViolation(e))return reply.code(409).send({error:"already_in_lobby"});req.log.error(e);return reply.code(500).send({error:"lobby_create_failed"});}
  finally{client.release();}
 });

 app.post("/lobbies/join",{config:{rateLimit:{max:12,timeWindow:"1 minute"}}},async(req,reply)=>{
  const playerId=await playerFromRequest(req,reply);if(!playerId)return;
  const parsed=joinBody.safeParse(req.body);if(!parsed.success)return reply.code(400).send({error:"invalid_invite_code"});
  const client=await pool.connect();
  try{
   await client.query("BEGIN");
   const found=await client.query<{id:string;region_id:string;status:string;max_members:number}>(
    "SELECT id,region_id,status,max_members FROM co_op_lobbies WHERE invite_code_hash=$1 FOR UPDATE",[digest(parsed.data.inviteCode)]);
   const lobby=found.rows[0];if(!lobby||!["open","in_world"].includes(lobby.status)){await client.query("ROLLBACK");return reply.code(404).send({error:"lobby_unavailable"});}
   const current=await client.query<{lobby_id:string}>("SELECT lobby_id FROM co_op_lobby_members WHERE player_id=$1 FOR UPDATE",[playerId]);
   if(current.rows[0]){await client.query("ROLLBACK");return reply.code(409).send({error:current.rows[0].lobby_id===lobby.id?"already_in_lobby":"already_in_another_lobby"});}
   const blocked=await client.query(
    "SELECT 1 FROM blocks b JOIN co_op_lobby_members m ON m.player_id=b.blocked_id WHERE m.lobby_id=$1 AND b.player_id=$2 UNION ALL SELECT 1 FROM blocks b JOIN co_op_lobby_members m ON m.player_id=b.player_id WHERE m.lobby_id=$1 AND b.blocked_id=$2 LIMIT 1",
    [lobby.id,playerId]);
   if(blocked.rowCount){await client.query("ROLLBACK");return reply.code(403).send({error:"blocked_player_in_lobby"});}
   const count=await client.query<{count:string}>("SELECT count(*)::text AS count FROM co_op_lobby_members WHERE lobby_id=$1",[lobby.id]);
   if(Number(count.rows[0]?.count??0)>=lobby.max_members){await client.query("ROLLBACK");return reply.code(409).send({error:"lobby_full"});}
   await client.query("INSERT INTO co_op_lobby_members(lobby_id,player_id,role) VALUES($1,$2,'member')",[lobby.id,playerId]);
   await client.query("INSERT INTO player_presence(player_id,state,region_id,last_heartbeat_at) VALUES($1,'in_lobby',$2,now()) ON CONFLICT(player_id) DO UPDATE SET state='in_lobby',region_id=EXCLUDED.region_id,last_heartbeat_at=now(),updated_at=now()",[playerId,lobby.region_id]);
   const seq=await client.query<{sequence:string}>("UPDATE co_op_lobbies SET next_event_sequence=next_event_sequence+1,updated_at=now() WHERE id=$1 RETURNING (next_event_sequence-1)::text AS sequence",[lobby.id]);
   await client.query("INSERT INTO co_op_world_events(lobby_id,sequence,event_type,actor_player_id,payload) VALUES($1,$2,'player_joined',$3,'{}'::jsonb)",[lobby.id,seq.rows[0]!.sequence,playerId]);
   await client.query("COMMIT");
   broadcast(lobby.id,{type:"player_joined",playerId,sequence:Number(seq.rows[0]!.sequence)});
   return{lobbyId:lobby.id,regionId:lobby.region_id,status:lobby.status};
  }catch(e){await client.query("ROLLBACK");if(isUniqueViolation(e))return reply.code(409).send({error:"already_in_another_lobby"});req.log.error(e);return reply.code(500).send({error:"lobby_join_failed"});}
  finally{client.release();}
 });

 app.get("/lobbies/current",async(req,reply)=>{
  const playerId=await playerFromRequest(req,reply);if(!playerId)return;
  const q=await pool.query(
   "SELECT l.id AS lobby_id,l.region_id,l.status,l.max_members,l.leader_player_id,m.role,p.id AS player_id,p.name,p.level FROM co_op_lobby_members mine JOIN co_op_lobbies l ON l.id=mine.lobby_id JOIN co_op_lobby_members m ON m.lobby_id=l.id JOIN players p ON p.id=m.player_id WHERE mine.player_id=$1 ORDER BY m.joined_at",
   [playerId]);
  if(!q.rowCount)return{lobby:null};
  const first=q.rows[0] as Record<string,unknown>;
  return{lobby:{id:first.lobby_id,regionId:first.region_id,status:first.status,maxMembers:first.max_members,leaderPlayerId:first.leader_player_id,members:q.rows.map(row=>({id:row.player_id,name:row.name,level:row.level,role:row.role}))}};
 });

 app.post("/lobbies/:lobbyId/leave",async(req,reply)=>{
  const playerId=await playerFromRequest(req,reply);if(!playerId)return;
  const params=idParams.safeParse(req.params);if(!params.success)return reply.code(400).send({error:"invalid_lobby_id"});
  const client=await pool.connect();
  try{
   await client.query("BEGIN");
   const found=await client.query<{leader_player_id:string;region_id:string}>("SELECT l.leader_player_id,l.region_id FROM co_op_lobbies l JOIN co_op_lobby_members m ON m.lobby_id=l.id WHERE l.id=$1 AND m.player_id=$2 FOR UPDATE OF l,m",[params.data.lobbyId,playerId]);
   if(!found.rowCount){await client.query("ROLLBACK");return reply.code(404).send({error:"lobby_membership_not_found"});}
   const lobby=found.rows[0]!;
   await client.query("DELETE FROM co_op_lobby_members WHERE lobby_id=$1 AND player_id=$2",[params.data.lobbyId,playerId]);
   const seq=await client.query<{sequence:string}>("UPDATE co_op_lobbies SET next_event_sequence=next_event_sequence+1,updated_at=now() WHERE id=$1 RETURNING (next_event_sequence-1)::text AS sequence",[params.data.lobbyId]);
   if(seq.rows[0])await client.query("INSERT INTO co_op_world_events(lobby_id,sequence,event_type,actor_player_id,payload) VALUES($1,$2,'player_left',$3,'{}'::jsonb)",[params.data.lobbyId,seq.rows[0].sequence,playerId]);
   if(lobby.leader_player_id===playerId){
    const next=await client.query<{player_id:string}>("SELECT player_id FROM co_op_lobby_members WHERE lobby_id=$1 ORDER BY joined_at LIMIT 1 FOR UPDATE",[params.data.lobbyId]);
    if(next.rows[0]){
     await client.query("UPDATE co_op_lobby_members SET role=CASE WHEN player_id=$2 THEN 'leader' ELSE 'member' END WHERE lobby_id=$1",[params.data.lobbyId,next.rows[0].player_id]);
     await client.query("UPDATE co_op_lobbies SET leader_player_id=$2,updated_at=now() WHERE id=$1",[params.data.lobbyId,next.rows[0].player_id]);
    }else{
     await client.query("UPDATE co_op_lobbies SET status='closed',updated_at=now() WHERE id=$1",[params.data.lobbyId]);
    }
   }
   await client.query("UPDATE player_presence SET state='online',region_id=NULL,updated_at=now() WHERE player_id=$1",[playerId]);
   await client.query("COMMIT");
   if(seq.rows[0])broadcast(params.data.lobbyId,{type:"player_left",playerId,sequence:Number(seq.rows[0].sequence)});
   return{status:"left"};
  }catch(e){await client.query("ROLLBACK");req.log.error(e);return reply.code(500).send({error:"lobby_leave_failed"});}
  finally{client.release();}
 });
};
