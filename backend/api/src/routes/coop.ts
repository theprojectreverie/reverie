import {titleName,verifiedTitleSql} from "./daily-quests.js";
import type {FastifyPluginAsync,FastifyRequest,FastifyReply} from "fastify";
import {createHash,randomBytes} from "node:crypto";
import {z} from "zod";
import {pool} from "../db.js";
import {broadcast,revokeLobbyMember} from "./realtime.js";
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
   await client.query("SELECT id FROM players WHERE id=$1 FOR UPDATE",[playerId]);
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
   await client.query("SELECT id FROM players WHERE id=$1 FOR UPDATE",[playerId]);
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
   const joined=(await client.query("SELECT p.name,"+verifiedTitleSql+" AS title_id FROM players p WHERE p.id=$1",[playerId])).rows[0];
    const joinedProfile={name:String(joined?.name??"Wanderer"),title:titleName(joined?.title_id)};
    await client.query("INSERT INTO co_op_world_events(lobby_id,sequence,event_type,actor_player_id,payload) VALUES($1,$2,'player_joined',$3,$4::jsonb)",[lobby.id,seq.rows[0]!.sequence,playerId,JSON.stringify(joinedProfile)]);
   await client.query("COMMIT");
   broadcast(lobby.id,{type:"player_joined",playerId,...joinedProfile,sequence:Number(seq.rows[0]!.sequence)});
   return{lobbyId:lobby.id,regionId:lobby.region_id,status:lobby.status};
  }catch(e){await client.query("ROLLBACK");if(isUniqueViolation(e))return reply.code(409).send({error:"already_in_another_lobby"});req.log.error(e);return reply.code(500).send({error:"lobby_join_failed"});}
  finally{client.release();}
 });

 // Direct invitations never expose the reusable lobby invite code.
 app.post("/friend-invites",{config:{rateLimit:{max:12,timeWindow:"1 minute"} }},async(req,reply)=>{
  const playerId=await playerFromRequest(req,reply);if(!playerId)return;
  const parsed=z.object({playerId:z.string().uuid()}).strict().safeParse(req.body);
  if(!parsed.success||parsed.data.playerId===playerId)return reply.code(400).send({error:"invalid_invite_target"});
  const target=parsed.data.playerId,db=await pool.connect();
  try{
   await db.query("BEGIN");
   const lobby=(await db.query("SELECT l.id,l.max_members FROM co_op_lobbies l JOIN co_op_lobby_members m ON m.lobby_id=l.id WHERE m.player_id=$1 AND l.leader_player_id=$1 AND l.status IN ('open','in_world') FOR UPDATE OF l",[playerId])).rows[0];
   if(!lobby){await db.query("ROLLBACK");return reply.code(409).send({error:"create_or_lead_party_first"});}
   await db.query("SELECT id FROM players WHERE id=ANY($1::uuid[]) ORDER BY id FOR UPDATE",[[playerId,target]]);
   const friend=await db.query("SELECT 1 FROM friendships f JOIN players p ON p.id=$2 JOIN accounts a ON a.id=p.account_id WHERE f.status='accepted' AND ((f.player_id=$1 AND f.friend_id=$2) OR (f.player_id=$2 AND f.friend_id=$1)) AND a.status='active' AND NOT EXISTS(SELECT 1 FROM blocks b WHERE (b.player_id=$1 AND b.blocked_id=$2) OR (b.player_id=$2 AND b.blocked_id=$1))",[playerId,target]);
   if(!friend.rowCount){await db.query("ROLLBACK");return reply.code(403).send({error:"friendship_required"});}
   if((await db.query("SELECT 1 FROM co_op_lobby_members WHERE player_id=$1",[target])).rowCount){await db.query("ROLLBACK");return reply.code(409).send({error:"friend_already_in_party"});}
   if(Number((await db.query("SELECT count(*) FROM co_op_lobby_members WHERE lobby_id=$1",[lobby.id])).rows[0].count)>=lobby.max_members){await db.query("ROLLBACK");return reply.code(409).send({error:"lobby_full"});}
   const invite=(await db.query("INSERT INTO co_op_friend_invites(lobby_id,sender_id,recipient_id) VALUES($1,$2,$3) ON CONFLICT(lobby_id,recipient_id) DO UPDATE SET sender_id=EXCLUDED.sender_id,expires_at=now()+interval '10 minutes' RETURNING id,expires_at",[lobby.id,playerId,target])).rows[0];
   await db.query("COMMIT");return reply.code(201).send({inviteId:invite.id,expiresAt:invite.expires_at});
  }catch(e){await db.query("ROLLBACK");throw e;}finally{db.release();}
 });
 app.post("/friend-invites/respond",async(req,reply)=>{
  const playerId=await playerFromRequest(req,reply);if(!playerId)return;
  const parsed=z.object({inviteId:z.string().uuid(),action:z.enum(["accept","decline"])}).strict().safeParse(req.body);
  if(!parsed.success)return reply.code(400).send({error:"invalid_invite"});
  const db=await pool.connect();
  try{
   await db.query("BEGIN");
   const invite=(await db.query("SELECT i.*,l.region_id,l.status,l.max_members,l.leader_player_id FROM co_op_friend_invites i JOIN co_op_lobbies l ON l.id=i.lobby_id WHERE i.id=$1 AND i.recipient_id=$2 AND i.expires_at>now() FOR UPDATE OF l,i",[parsed.data.inviteId,playerId])).rows[0];
   if(!invite){await db.query("ROLLBACK");return reply.code(404).send({error:"invite_unavailable"});}
   if(parsed.data.action==="decline"){await db.query("DELETE FROM co_op_friend_invites WHERE id=$1",[invite.id]);await db.query("COMMIT");return {status:"declined"};}
   if(!["open","in_world"].includes(invite.status)||invite.sender_id!==invite.leader_player_id){await db.query("ROLLBACK");return reply.code(409).send({error:"lobby_unavailable"});}
   await db.query("SELECT id FROM players WHERE id=ANY($1::uuid[]) ORDER BY id FOR UPDATE",[[playerId,invite.sender_id]]);
   const friend=await db.query("SELECT 1 FROM friendships f JOIN players p ON p.id=$2 JOIN accounts a ON a.id=p.account_id WHERE f.status='accepted' AND ((f.player_id=$1 AND f.friend_id=$2) OR (f.player_id=$2 AND f.friend_id=$1)) AND a.status='active'",[playerId,invite.sender_id]);
   const blocked=await db.query("SELECT 1 FROM blocks b JOIN co_op_lobby_members m ON m.player_id=b.blocked_id WHERE m.lobby_id=$1 AND b.player_id=$2 UNION ALL SELECT 1 FROM blocks b JOIN co_op_lobby_members m ON m.player_id=b.player_id WHERE m.lobby_id=$1 AND b.blocked_id=$2 LIMIT 1",[invite.lobby_id,playerId]);
   if(!friend.rowCount||blocked.rowCount){await db.query("ROLLBACK");return reply.code(403).send({error:"friendship_or_block_restriction"});}
   if((await db.query("SELECT 1 FROM co_op_lobby_members WHERE player_id=$1",[playerId])).rowCount){await db.query("ROLLBACK");return reply.code(409).send({error:"already_in_lobby"});}
   if(Number((await db.query("SELECT count(*) FROM co_op_lobby_members WHERE lobby_id=$1",[invite.lobby_id])).rows[0].count)>=invite.max_members){await db.query("ROLLBACK");return reply.code(409).send({error:"lobby_full"});}
   await db.query("INSERT INTO co_op_lobby_members(lobby_id,player_id,role) VALUES($1,$2,'member')",[invite.lobby_id,playerId]);
   await db.query("INSERT INTO player_presence(player_id,state,region_id,last_heartbeat_at) VALUES($1,'in_lobby',$2,now()) ON CONFLICT(player_id) DO UPDATE SET state='in_lobby',region_id=EXCLUDED.region_id,last_heartbeat_at=now(),updated_at=now()",[playerId,invite.region_id]);
   const seq=Number((await db.query("UPDATE co_op_lobbies SET next_event_sequence=next_event_sequence+1,updated_at=now() WHERE id=$1 RETURNING next_event_sequence-1 AS sequence",[invite.lobby_id])).rows[0].sequence);
   const joined=(await db.query("SELECT p.name,"+verifiedTitleSql+" AS title_id FROM players p WHERE p.id=$1",[playerId])).rows[0];
    const joinedProfile={name:String(joined?.name??"Wanderer"),title:titleName(joined?.title_id)};
    await db.query("INSERT INTO co_op_world_events(lobby_id,sequence,event_type,actor_player_id,payload) VALUES($1,$2,'player_joined',$3,$4::jsonb)",[invite.lobby_id,seq,playerId,JSON.stringify(joinedProfile)]);
   await db.query("DELETE FROM co_op_friend_invites WHERE recipient_id=$1",[playerId]);
   await db.query("COMMIT");
   broadcast(invite.lobby_id,{type:"player_joined",playerId,...joinedProfile,sequence:seq});
   return {status:"accepted",lobbyId:invite.lobby_id,regionId:invite.region_id};
  }catch(e){await db.query("ROLLBACK");if(isUniqueViolation(e))return reply.code(409).send({error:"already_in_lobby"});throw e;}finally{db.release();}
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
   revokeLobbyMember(params.data.lobbyId,playerId);
   if(seq.rows[0])broadcast(params.data.lobbyId,{type:"player_left",playerId,sequence:Number(seq.rows[0].sequence)});
   return{status:"left"};
  }catch(e){await client.query("ROLLBACK");req.log.error(e);return reply.code(500).send({error:"lobby_leave_failed"});}
  finally{client.release();}
 });
};
