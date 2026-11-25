import type {FastifyPluginAsync,FastifyRequest,FastifyReply} from "fastify";
import {createHash,randomBytes,randomUUID,timingSafeEqual} from "node:crypto";
import {z} from "zod";
import {pool} from "../db.js";
import {config} from "../config.js";
import {hasContiguousEventSequences} from "../world/persistent-replay-window.js";

type Claims={sub?:string;playerId?:string;tokenVersion?:number};
const registerBody=z.object({
 serverKey:z.string().trim().toLowerCase().regex(/^[a-z0-9][a-z0-9_-]{2,63}$/),
 displayName:z.string().trim().min(3).max(48),
 regionId:z.string().trim().toLowerCase().regex(/^[a-z0-9_]{2,48}$/),
 endpointUrl:z.string().url().refine(v=>v.startsWith("ws://")||v.startsWith("wss://")).optional(),
 maxPlayers:z.number().int().min(1).max(1000).default(100),
 buildVersion:z.string().trim().min(1).max(40).default("development")
});
const heartbeatBody=z.object({status:z.enum(["online","draining","maintenance","offline"])});
const ticketBody=z.object({ticket:z.string().min(40).max(200),connectionId:z.string().uuid().optional()});
const worldStateBody=z.object({revision:z.number().int().nonnegative().max(Number.MAX_SAFE_INTEGER),state:z.record(z.string(),z.unknown())});
const worldEventBody=z.object({
 eventId:z.string().uuid(),
 type:z.enum(["position","emote","player_joined"]),
 playerId:z.string().uuid(),
 payload:z.record(z.string(),z.unknown()).default({})
});
const worldEventCursor=z.object({after:z.coerce.number().int().nonnegative().max(Number.MAX_SAFE_INTEGER).default(0)});
const connectionLeaseParams=z.object({serverId:z.string().uuid(),connectionId:z.string().uuid()});
const digest=(v:string)=>createHash("sha256").update(v).digest("hex");
function secretMatches(candidate:string,expected:string):boolean{
 const a=Buffer.from(candidate);const b=Buffer.from(expected);
 return a.length===b.length&&timingSafeEqual(a,b);
}
async function playerFromRequest(req:FastifyRequest,reply:FastifyReply):Promise<string|null>{
 try{
  await req.jwtVerify();
  const c=req.user as Claims;
  if(!c.sub||!c.playerId||!Number.isInteger(c.tokenVersion))throw new Error("invalid_claims");
  const q=await pool.query<{token_version:number;status:string}>("SELECT token_version,status FROM accounts WHERE id=$1",[c.sub]);
  if(q.rows[0]?.status==="active"&&q.rows[0].token_version===c.tokenVersion)return c.playerId;
 }catch{/* fail closed */}
 reply.code(401).send({error:"authentication_required"});return null;
}
async function serverFromRequest(req:FastifyRequest,reply:FastifyReply):Promise<string|null>{
 const header=req.headers.authorization??"";
 const token=header.startsWith("Bearer ")?header.slice(7):"";
 if(token.length<32){reply.code(401).send({error:"server_authentication_required"});return null;}
 try{
  const q=await pool.query<{id:string}>("SELECT id FROM game_servers WHERE server_secret_hash=$1",[digest(token)]);
  if(q.rows[0])return q.rows[0].id;
 }catch(error){req.log.error(error);}
 reply.code(401).send({error:"server_authentication_required"});return null;
}

export const gameServerRoutes:FastifyPluginAsync=async app=>{
 // Release abandoned join reservations even when no player requests another join.
 // Redeemed tickets always preserve their assignment; a newer live ticket also wins
 // over an older expired ticket for the same player/server pair.
 let cleanupRunning=false;
 const cleanupTimer=setInterval(async()=>{
  if(cleanupRunning)return;
  cleanupRunning=true;
  const client=await pool.connect().catch(error=>{app.log.error(error,"join reservation cleanup connection failed");return null;});
  if(!client){cleanupRunning=false;return;}
  try{
   await client.query("BEGIN");
   await client.query(
    "DELETE FROM game_server_players p WHERE EXISTS(SELECT 1 FROM game_server_join_tickets t WHERE t.server_id=p.server_id AND t.player_id=p.player_id AND t.consumed_at IS NULL AND t.expires_at<=now()) AND NOT EXISTS(SELECT 1 FROM game_server_join_tickets t WHERE t.server_id=p.server_id AND t.player_id=p.player_id AND t.consumed_at IS NOT NULL) AND NOT EXISTS(SELECT 1 FROM game_server_join_tickets t WHERE t.server_id=p.server_id AND t.player_id=p.player_id AND t.consumed_at IS NULL AND t.expires_at>now())"
   );
   await client.query("UPDATE game_server_join_tickets SET consumed_at=now() WHERE consumed_at IS NULL AND expires_at<=now()");
   await client.query("COMMIT");
  }catch(error){
   await client.query("ROLLBACK").catch(()=>undefined);
   app.log.error(error,"join reservation cleanup failed");
  }finally{
   client.release();
   cleanupRunning=false;
  }
 },15000);
 cleanupTimer.unref();
 app.addHook("onClose",async()=>clearInterval(cleanupTimer));

 app.post("/register",{config:{rateLimit:{max:5,timeWindow:"15 minutes"}}},async(req,reply)=>{
  const bootstrap=String(req.headers["x-server-bootstrap-secret"]??"");
  if(!config.GAME_SERVER_BOOTSTRAP_SECRET||!secretMatches(bootstrap,config.GAME_SERVER_BOOTSTRAP_SECRET))
   return reply.code(401).send({error:"server_registration_unauthorized"});
  const parsed=registerBody.safeParse(req.body);
  if(!parsed.success)return reply.code(400).send({error:"invalid_server_registration"});
  const token=randomBytes(48).toString("base64url");
  try{
   // Reclaiming a stale server identity invalidates every socket owned by the old process.
   // Delete its leases in the same statement as token rotation, but preserve player assignments and positions.
   const q=await pool.query<{id:string}>(
    "WITH registered AS (INSERT INTO game_servers(server_key,display_name,region_id,status,endpoint_url,server_secret_hash,max_players,build_version,heartbeat_at,started_at,stopped_at) VALUES($1,$2,$3,'starting',$4,$5,$6,$7,NULL,now(),NULL) ON CONFLICT(server_key) DO UPDATE SET display_name=EXCLUDED.display_name,region_id=EXCLUDED.region_id,status='starting',endpoint_url=EXCLUDED.endpoint_url,server_secret_hash=EXCLUDED.server_secret_hash,max_players=EXCLUDED.max_players,build_version=EXCLUDED.build_version,heartbeat_at=NULL,started_at=now(),stopped_at=NULL,updated_at=now() WHERE game_servers.status='offline' OR game_servers.heartbeat_at<now()-interval '60 seconds' OR (game_servers.heartbeat_at IS NULL AND game_servers.started_at<now()-interval '60 seconds') RETURNING id), released AS (DELETE FROM game_server_player_connections c USING registered r WHERE c.server_id=r.id RETURNING c.connection_id) SELECT id FROM registered",
    [parsed.data.serverKey,parsed.data.displayName,parsed.data.regionId,parsed.data.endpointUrl??null,digest(token),parsed.data.maxPlayers,parsed.data.buildVersion]);
   if(!q.rows[0])return reply.code(409).send({error:"server_key_unavailable"});
   return reply.code(201).send({serverId:q.rows[0].id,serverToken:token,status:"starting"});
  }catch(error){
   if(typeof error==="object"&&error!==null&&"code" in error&&(error as {code?:string}).code==="23505")
    return reply.code(409).send({error:"server_key_unavailable"});
   req.log.error(error);return reply.code(500).send({error:"server_registration_failed"});
  }
 });

 app.post("/:serverId/heartbeat",{config:{rateLimit:{max:120,timeWindow:"1 minute"}}},async(req,reply)=>{
  const serverId=await serverFromRequest(req,reply);if(!serverId)return;
  const params=z.object({serverId:z.string().uuid()}).safeParse(req.params);
  const parsed=heartbeatBody.safeParse(req.body);
  if(!params.success||!parsed.success)return reply.code(400).send({error:"invalid_server_heartbeat"});
  if(params.data.serverId!==serverId)return reply.code(403).send({error:"server_identity_mismatch"});
  const client=await pool.connect();
  try{
   await client.query("BEGIN");
   const q=await client.query(
    "UPDATE game_servers SET status=$2,heartbeat_at=now(),stopped_at=CASE WHEN $2='offline' THEN now() ELSE NULL END,updated_at=now() WHERE id=$1 RETURNING id",
    [serverId,parsed.data.status]);
   if(!q.rowCount){await client.query("ROLLBACK");return reply.code(404).send({error:"server_not_found"});}
   if(parsed.data.status==="offline"){
    await client.query("UPDATE game_server_join_tickets SET consumed_at=now() WHERE server_id=$1 AND consumed_at IS NULL",[serverId]);
    await client.query("DELETE FROM game_server_players WHERE server_id=$1",[serverId]);
   }
   await client.query("COMMIT");
   return{status:"accepted",serverId,heartbeatAt:new Date().toISOString()};
  }catch(error){
   await client.query("ROLLBACK");
   req.log.error(error);
   return reply.code(500).send({error:"server_heartbeat_failed"});
  }finally{client.release();}
 });

 app.get("/",async(req,reply)=>{
  const playerId=await playerFromRequest(req,reply);if(!playerId)return;
  const q=await pool.query(
   "SELECT s.id,s.server_key,s.display_name,s.region_id,s.status,s.endpoint_url,s.max_players,count(p.player_id)::int AS current_players,s.build_version FROM game_servers s LEFT JOIN game_server_players p ON p.server_id=s.id WHERE s.status='online' AND s.heartbeat_at>now()-interval '60 seconds' GROUP BY s.id ORDER BY s.region_id,s.display_name");
  return{servers:q.rows};
 });

 app.post("/:serverId/join",{config:{rateLimit:{max:10,timeWindow:"1 minute"}}},async(req,reply)=>{
  const playerId=await playerFromRequest(req,reply);if(!playerId)return;
  const params=z.object({serverId:z.string().uuid()}).safeParse(req.params);
  if(!params.success)return reply.code(400).send({error:"invalid_server_id"});
  const client=await pool.connect();
  const joinTicket=randomBytes(32).toString("base64url");
  try{
   await client.query("BEGIN");
   const server=await client.query<{id:string;endpoint_url:string|null;max_players:number}>(
    "SELECT id,endpoint_url,max_players FROM game_servers WHERE id=$1 AND status='online' AND heartbeat_at>now()-interval '60 seconds' FOR UPDATE",
    [params.data.serverId]);
   if(!server.rows[0]){await client.query("ROLLBACK");return reply.code(404).send({error:"server_unavailable"});}
   if(!server.rows[0].endpoint_url){await client.query("ROLLBACK");return reply.code(503).send({error:"server_transport_unavailable"});}
   // A reserved slot is provisional until its ticket is redeemed. Release abandoned
   // reservations after expiry, but never evict a player with a redeemed ticket.
   await client.query("DELETE FROM game_server_players p WHERE p.server_id=$1 AND EXISTS(SELECT 1 FROM game_server_join_tickets t WHERE t.server_id=p.server_id AND t.player_id=p.player_id AND t.consumed_at IS NULL AND t.expires_at<=now()) AND NOT EXISTS(SELECT 1 FROM game_server_join_tickets t WHERE t.server_id=p.server_id AND t.player_id=p.player_id AND t.consumed_at IS NOT NULL) AND NOT EXISTS(SELECT 1 FROM game_server_join_tickets t WHERE t.server_id=p.server_id AND t.player_id=p.player_id AND t.consumed_at IS NULL AND t.expires_at>now())",[params.data.serverId]);
   await client.query("UPDATE game_server_join_tickets SET consumed_at=now() WHERE server_id=$1 AND consumed_at IS NULL AND expires_at<=now()",[params.data.serverId]);
   const existing=await client.query<{server_id:string}>("SELECT server_id FROM game_server_players WHERE player_id=$1 FOR UPDATE",[playerId]);
   if(existing.rows[0]){
    await client.query("ROLLBACK");
    return reply.code(409).send({error:existing.rows[0].server_id===params.data.serverId?"already_on_server":"leave_current_server_first"});
   }
   const count=await client.query<{count:string}>("SELECT count(*)::text AS count FROM game_server_players WHERE server_id=$1",[params.data.serverId]);
   if(Number(count.rows[0]?.count??0)>=server.rows[0].max_players){await client.query("ROLLBACK");return reply.code(409).send({error:"server_full"});}
   await client.query("UPDATE game_server_join_tickets SET consumed_at=now() WHERE player_id=$1 AND consumed_at IS NULL",[playerId]);
   await client.query("INSERT INTO game_server_players(server_id,player_id) VALUES($1,$2)",[params.data.serverId,playerId]);
   const ticket=await client.query<{expires_at:Date}>("INSERT INTO game_server_join_tickets(server_id,player_id,ticket_hash,expires_at) VALUES($1,$2,$3,now()+interval '60 seconds') RETURNING expires_at",[params.data.serverId,playerId,digest(joinTicket)]);
   await client.query("COMMIT");
   return{status:"joined",serverId:server.rows[0].id,endpointUrl:server.rows[0].endpoint_url,joinTicket, ticketExpiresAt:ticket.rows[0]!.expires_at};
  }catch(error){
   await client.query("ROLLBACK");
   if(typeof error==="object"&&error!==null&&"code" in error&&(error as {code?:string}).code==="23505")
    return reply.code(409).send({error:"already_on_server"});
   req.log.error(error);return reply.code(500).send({error:"server_join_failed"});
  }finally{client.release();}
 });

 app.post("/:serverId/consume-ticket",{config:{rateLimit:{max:60,timeWindow:"1 minute"}}},async(req,reply)=>{
  const authenticatedServer=await serverFromRequest(req,reply);if(!authenticatedServer)return;
  const params=z.object({serverId:z.string().uuid()}).safeParse(req.params);
  const parsed=ticketBody.safeParse(req.body);
  if(!params.success||!parsed.success)return reply.code(400).send({error:"invalid_join_ticket_request"});
  if(params.data.serverId!==authenticatedServer)return reply.code(403).send({error:"server_identity_mismatch"});
  const client=await pool.connect();
  try{
   await client.query("BEGIN");
   await client.query("SELECT id FROM game_servers WHERE id=$1 FOR UPDATE",[authenticatedServer]);
   const ticket=await client.query<{player_id:string;player_name:string;player_level:number}>("SELECT t.player_id,p.name AS player_name,p.level AS player_level FROM game_server_join_tickets t JOIN game_server_players gp ON gp.server_id=t.server_id AND gp.player_id=t.player_id JOIN players p ON p.id=t.player_id JOIN accounts ac ON ac.id=p.account_id AND ac.status='active' AND ac.email_verified=true JOIN game_servers s ON s.id=t.server_id WHERE t.server_id=$1 AND t.ticket_hash=$2 AND t.consumed_at IS NULL AND t.expires_at>now() AND s.status IN('online','draining') FOR UPDATE OF t,gp",[authenticatedServer,digest(parsed.data.ticket)]);
   if(!ticket.rows[0]){await client.query("ROLLBACK");return reply.code(401).send({error:"join_ticket_invalid_or_expired"});}
   if(parsed.data.connectionId){
    await client.query("DELETE FROM game_server_player_connections WHERE server_id=$1 AND player_id=$2 AND lease_expires_at<=now()",[authenticatedServer,ticket.rows[0].player_id]);
    const active=await client.query<{count:string}>("SELECT count(*)::text AS count FROM game_server_player_connections WHERE server_id=$1 AND player_id=$2 AND lease_expires_at>now()",[authenticatedServer,ticket.rows[0].player_id]);
    if(Number(active.rows[0]?.count??0)>=2){await client.query("ROLLBACK");return reply.code(409).send({error:"connection_limit"});}
    await client.query("INSERT INTO game_server_player_connections(connection_id,server_id,player_id,lease_expires_at) VALUES($1,$2,$3,now()+interval '45 seconds')",[parsed.data.connectionId,authenticatedServer,ticket.rows[0].player_id]);
   }
   await client.query("UPDATE game_server_join_tickets SET consumed_at=now() WHERE server_id=$1 AND ticket_hash=$2",[authenticatedServer,digest(parsed.data.ticket)]);
   await client.query("UPDATE game_server_players SET last_seen_at=now() WHERE server_id=$1 AND player_id=$2",[authenticatedServer,ticket.rows[0].player_id]);
   await client.query("COMMIT");
   return{status:"accepted",serverId:authenticatedServer,playerId:ticket.rows[0].player_id,connectionId:parsed.data.connectionId??null,player:{name:ticket.rows[0].player_name,level:ticket.rows[0].player_level}};
  }catch(error){
   await client.query("ROLLBACK");req.log.error(error);return reply.code(500).send({error:"join_ticket_validation_failed"});
  }finally{client.release();}
 });

 app.post("/:serverId/reconnect",{config:{rateLimit:{max:12,timeWindow:"1 minute"}}},async(req,reply)=>{
  const playerId=await playerFromRequest(req,reply);if(!playerId)return;
  const params=z.object({serverId:z.string().uuid()}).safeParse(req.params);
  if(!params.success)return reply.code(400).send({error:"invalid_server_id"});
  const joinTicket=randomBytes(32).toString("base64url");
  const client=await pool.connect();
  try{
   await client.query("BEGIN");
   const server=await client.query<{id:string;endpoint_url:string|null}>("SELECT id,endpoint_url FROM game_servers WHERE id=$1 AND status IN('online','draining') AND heartbeat_at>now()-interval '60 seconds' FOR UPDATE",[params.data.serverId]);
   if(!server.rows[0]){await client.query("ROLLBACK");return reply.code(404).send({error:"server_unavailable"});}
   if(!server.rows[0].endpoint_url){await client.query("ROLLBACK");return reply.code(503).send({error:"server_transport_unavailable"});}
   const assignment=await client.query("SELECT 1 FROM game_server_players WHERE server_id=$1 AND player_id=$2 FOR UPDATE",[params.data.serverId,playerId]);
   if(!assignment.rowCount){await client.query("ROLLBACK");return reply.code(404).send({error:"server_assignment_expired"});}
   await client.query("UPDATE game_server_join_tickets SET consumed_at=now() WHERE server_id=$1 AND player_id=$2 AND consumed_at IS NULL",[params.data.serverId,playerId]);
   const ticket=await client.query<{expires_at:Date}>("INSERT INTO game_server_join_tickets(server_id,player_id,ticket_hash,expires_at) VALUES($1,$2,$3,now()+interval '60 seconds') RETURNING expires_at",[params.data.serverId,playerId,digest(joinTicket)]);
   await client.query("COMMIT");
   return{status:"reconnecting",serverId:server.rows[0].id,endpointUrl:server.rows[0].endpoint_url,joinTicket,ticketExpiresAt:ticket.rows[0]!.expires_at};
  }catch(error){
   await client.query("ROLLBACK");req.log.error(error);return reply.code(500).send({error:"server_reconnect_failed"});
  }finally{client.release();}
 });

 app.post("/:serverId/disconnect",async(req,reply)=>{
  const serverId=await serverFromRequest(req,reply);if(!serverId)return;
  const params=z.object({serverId:z.string().uuid()}).safeParse(req.params);
  const body=z.object({playerId:z.string().uuid()}).safeParse(req.body);
  if(!params.success||!body.success)return reply.code(400).send({error:"invalid_server_disconnect"});
  if(params.data.serverId!==serverId)return reply.code(403).send({error:"server_identity_mismatch"});
  const client=await pool.connect();
  try{
   await client.query("BEGIN");
   await client.query("SELECT id FROM game_servers WHERE id=$1 FOR UPDATE",[serverId]);
   const assignment=await client.query("SELECT 1 FROM game_server_players WHERE server_id=$1 AND player_id=$2 FOR UPDATE",[serverId,body.data.playerId]);
   if(!assignment.rowCount){
    const lastEvent=await client.query<{sequence:string}>("SELECT sequence::text FROM game_server_world_events WHERE server_id=$1 AND player_id=$2 AND event_type='player_left' ORDER BY sequence DESC LIMIT 1",[serverId,body.data.playerId]);
    const current=await client.query<{sequence:string}>("SELECT next_event_sequence::text AS sequence FROM game_servers WHERE id=$1",[serverId]);
    await client.query("COMMIT");
    return{status:"already_disconnected",sequence:Number(lastEvent.rows[0]?.sequence??current.rows[0]?.sequence??0)};
   }
   await client.query("DELETE FROM game_server_player_connections WHERE server_id=$1 AND player_id=$2 AND lease_expires_at<=now()",[serverId,body.data.playerId]);
   const presence=await client.query<{active:boolean}>(
    "SELECT EXISTS(SELECT 1 FROM game_server_player_connections WHERE server_id=$1 AND player_id=$2 AND lease_expires_at>now()) OR EXISTS(SELECT 1 FROM game_server_join_tickets WHERE server_id=$1 AND player_id=$2 AND consumed_at IS NULL AND expires_at>now()) AS active",
    [serverId,body.data.playerId]);
   if(presence.rows[0]?.active){await client.query("ROLLBACK");return reply.code(409).send({error:"player_still_connected"});}
   await client.query("UPDATE game_server_join_tickets SET consumed_at=now() WHERE server_id=$1 AND player_id=$2 AND consumed_at IS NULL",[serverId,body.data.playerId]);
   await client.query("DELETE FROM game_server_player_state WHERE server_id=$1 AND player_id=$2",[serverId,body.data.playerId]);
   await client.query("DELETE FROM game_server_players WHERE server_id=$1 AND player_id=$2",[serverId,body.data.playerId]);
   const eventId=randomUUID();
   const event=await client.query<{sequence:string}>(
    "WITH bumped AS (UPDATE game_servers SET next_event_sequence=next_event_sequence+1,updated_at=now() WHERE id=$1 RETURNING next_event_sequence), inserted AS (INSERT INTO game_server_world_events(server_id,sequence,event_id,event_type,player_id,payload) SELECT $1,next_event_sequence,$3,'player_left',$2,'{}'::jsonb FROM bumped RETURNING sequence) SELECT sequence::text FROM inserted",
    [serverId,body.data.playerId,eventId]);
   if(!event.rows[0])throw new Error("world_event_server_missing");
   const sequence=Number(event.rows[0].sequence);
   await client.query("SELECT pg_notify('reverie_world_events',$1)",[JSON.stringify({serverId,payload:{type:"player_left",playerId:body.data.playerId,sequence},origin:"dedicated-godot:"+serverId})]);
   await client.query("COMMIT");
   return{status:"disconnected",sequence};
  }catch(error){
   await client.query("ROLLBACK").catch(()=>undefined);req.log.error(error);
   return reply.code(500).send({error:"server_disconnect_failed"});
  }finally{client.release();}
 });
  app.post("/:serverId/leave",async(req,reply)=>{
  const playerId=await playerFromRequest(req,reply);if(!playerId)return;
  const params=z.object({serverId:z.string().uuid()}).safeParse(req.params);
  if(!params.success)return reply.code(400).send({error:"invalid_server_id"});
  const client=await pool.connect();
  let q;
  try{
   await client.query("BEGIN");
   await client.query("UPDATE game_server_join_tickets SET consumed_at=now() WHERE server_id=$1 AND player_id=$2 AND consumed_at IS NULL",[params.data.serverId,playerId]);
   await client.query("DELETE FROM game_server_player_state WHERE server_id=$1 AND player_id=$2",[params.data.serverId,playerId]);
   q=await client.query("DELETE FROM game_server_players WHERE server_id=$1 AND player_id=$2 RETURNING player_id",[params.data.serverId,playerId]);
   await client.query("COMMIT");
  }catch(error){await client.query("ROLLBACK");req.log.error(error);return reply.code(500).send({error:"server_leave_failed"});}
  finally{client.release();}
  if(!q.rowCount)return reply.code(404).send({error:"server_assignment_not_found"});
  return{status:"left"};
 });

 app.post("/:serverId/events",{config:{rateLimit:{max:3000,timeWindow:"1 minute"}}},async(req,reply)=>{
  const serverId=await serverFromRequest(req,reply);if(!serverId)return;
  const params=z.object({serverId:z.string().uuid()}).safeParse(req.params);
  const parsed=worldEventBody.safeParse(req.body);
  if(!params.success||!parsed.success)return reply.code(400).send({error:"invalid_world_event"});
  if(params.data.serverId!==serverId)return reply.code(403).send({error:"server_identity_mismatch"});
  const {eventId,type,playerId,payload}=parsed.data;
  if(type==="position"&&!z.object({x:z.number().finite().min(-100000).max(100000),y:z.number().finite().min(-100000).max(100000)}).safeParse(payload).success)
   return reply.code(400).send({error:"invalid_world_event_payload"});
  if(type==="emote"&&!z.object({emoteId:z.enum(["wave","cheer","sad","dance"])}).safeParse(payload).success)
   return reply.code(400).send({error:"invalid_world_event_payload"});
  if(Buffer.byteLength(JSON.stringify(payload),"utf8")>4096)return reply.code(413).send({error:"world_event_too_large"});
  const client=await pool.connect();
  try{
   await client.query("BEGIN");
   await client.query("SELECT id FROM game_servers WHERE id=$1 FOR UPDATE",[serverId]);
   const existing=await client.query<{sequence:string;same_payload:boolean;same_type:boolean;same_player:boolean}>(
    "SELECT sequence::text,(payload=$3::jsonb) AS same_payload,(event_type=$4) AS same_type,(player_id=$5) AS same_player FROM game_server_world_events WHERE server_id=$1 AND event_id=$2",
    [serverId,eventId,JSON.stringify(payload),type,playerId]);
   if(existing.rows[0]){
    if(!existing.rows[0].same_payload||!existing.rows[0].same_type||!existing.rows[0].same_player){
     await client.query("ROLLBACK");
     return reply.code(409).send({error:"world_event_id_conflict"});
    }
    await client.query("COMMIT");
    return{status:"committed",sequence:Number(existing.rows[0].sequence),duplicate:true};
   }
   const assignment=await client.query("SELECT 1 FROM game_server_players WHERE server_id=$1 AND player_id=$2 FOR UPDATE",[serverId,playerId]);
   if(!assignment.rowCount){await client.query("ROLLBACK");return reply.code(409).send({error:"server_assignment_required"});}
   const bumped=await client.query<{next_event_sequence:string}>("UPDATE game_servers SET next_event_sequence=next_event_sequence+1,updated_at=now() WHERE id=$1 RETURNING next_event_sequence::text",[serverId]);
   if(!bumped.rows[0])throw new Error("world_event_server_missing");
   const sequence=Number(bumped.rows[0].next_event_sequence);
   if(type==="position"){
    await client.query(
     "INSERT INTO game_server_player_state(server_id,player_id,x,y,updated_at) VALUES($1,$2,$3,$4,now()) ON CONFLICT(server_id,player_id) DO UPDATE SET x=EXCLUDED.x,y=EXCLUDED.y,updated_at=now()",
     [serverId,playerId,(payload as {x:number}).x,(payload as {y:number}).y]);
   }
   await client.query(
    "INSERT INTO game_server_world_events(server_id,sequence,event_id,event_type,player_id,payload) VALUES($1,$2,$3,$4,$5,$6::jsonb)",
    [serverId,sequence,eventId,type,playerId,JSON.stringify(payload)]);
   const notification={...payload,type,playerId,sequence};
   await client.query("SELECT pg_notify('reverie_world_events',$1)",[JSON.stringify({serverId,payload:notification,origin:"dedicated-godot:"+serverId})]);
   await client.query("COMMIT");
   return{status:"committed",sequence};
  }catch(error){
   await client.query("ROLLBACK").catch(()=>undefined);req.log.error(error,"dedicated world event persistence failed");
   return reply.code(500).send({error:"world_event_persistence_failed"});
  }finally{client.release();}
 });

 app.get("/:serverId/events",async(req,reply)=>{
  const serverId=await serverFromRequest(req,reply);if(!serverId)return;
  const params=z.object({serverId:z.string().uuid()}).safeParse(req.params);
  const cursor=worldEventCursor.safeParse(req.query);
  if(!params.success||!cursor.success)return reply.code(400).send({error:"invalid_world_event_cursor"});
  if(params.data.serverId!==serverId)return reply.code(403).send({error:"server_identity_mismatch"});
  const client=await pool.connect();
  try{
   await client.query("BEGIN ISOLATION LEVEL REPEATABLE READ READ ONLY");
   const window=await client.query<{oldest_sequence:string|null;current_sequence:string}>(
    "SELECT (SELECT min(sequence)::text FROM game_server_world_events WHERE server_id=$1) AS oldest_sequence,next_event_sequence::text AS current_sequence FROM game_servers WHERE id=$1",
    [serverId]);
   if(!window.rows[0]){await client.query("COMMIT");return reply.code(404).send({error:"server_not_found"});}
   const currentSequence=Number(window.rows[0].current_sequence);
   if(cursor.data.after>currentSequence){await client.query("COMMIT");return reply.code(409).send({error:"replay_cursor_ahead",currentSequence});}
   const events=await client.query<{sequence:string;event_type:string;player_id:string|null;payload:Record<string,unknown>}>(
    "SELECT sequence::text,event_type,player_id,payload FROM game_server_world_events WHERE server_id=$1 AND sequence>$2 ORDER BY sequence ASC LIMIT 201",
    [serverId,cursor.data.after]);
   const replaySequences=events.rows.slice(0,200).map(event=>Number(event.sequence));
   const requiresSnapshot=events.rows.length>200
    ||(currentSequence>cursor.data.after&&(window.rows[0].oldest_sequence===null||cursor.data.after<Number(window.rows[0].oldest_sequence)-1))
    ||!hasContiguousEventSequences(cursor.data.after,currentSequence,replaySequences);
   const positions=requiresSnapshot?await client.query<{player_id:string;x:number;y:number}>(
    "SELECT player_id,x,y FROM game_server_player_state WHERE server_id=$1 ORDER BY player_id",[serverId]):null;
   const response={
    oldestSequence:window.rows[0].oldest_sequence===null?null:Number(window.rows[0].oldest_sequence),
    currentSequence,
    requiresSnapshot,
    positions:positions?.rows.map(position=>({playerId:position.player_id,x:position.x,y:position.y}))??[],
    events:events.rows.slice(0,200).map(event=>({...event.payload,sequence:Number(event.sequence),type:event.event_type,playerId:event.player_id}))
   };
   await client.query("COMMIT");
   return response;
  }catch(error){
   await client.query("ROLLBACK").catch(()=>undefined);req.log.error(error,"persistent world replay query failed");
   return reply.code(500).send({error:"world_event_replay_failed"});
  }finally{client.release();}
 });
  app.put("/:serverId/connections/:connectionId",async(req,reply)=>{
  const serverId=await serverFromRequest(req,reply);if(!serverId)return;
  const params=connectionLeaseParams.safeParse(req.params);
  if(!params.success)return reply.code(400).send({error:"invalid_connection_lease"});
  if(params.data.serverId!==serverId)return reply.code(403).send({error:"server_identity_mismatch"});
  const renewed=await pool.query("UPDATE game_server_player_connections SET lease_expires_at=now()+interval '45 seconds' WHERE connection_id=$1 AND server_id=$2 AND lease_expires_at>now() RETURNING connection_id",[params.data.connectionId,serverId]);
  if(!renewed.rowCount)return reply.code(409).send({error:"connection_lease_lost"});
  return{status:"renewed",leaseSeconds:45};
 });

 app.delete("/:serverId/connections/:connectionId",async(req,reply)=>{
  const serverId=await serverFromRequest(req,reply);if(!serverId)return;
  const params=connectionLeaseParams.safeParse(req.params);
  if(!params.success)return reply.code(400).send({error:"invalid_connection_lease"});
  if(params.data.serverId!==serverId)return reply.code(403).send({error:"server_identity_mismatch"});
  await pool.query("DELETE FROM game_server_player_connections WHERE connection_id=$1 AND server_id=$2",[params.data.connectionId,serverId]);
  return{status:"released"};
 });

 app.get("/:serverId/world-state",async(req,reply)=>{
  const serverId=await serverFromRequest(req,reply);if(!serverId)return;
  const params=z.object({serverId:z.string().uuid()}).safeParse(req.params);
  if(!params.success)return reply.code(400).send({error:"invalid_server_id"});
  if(params.data.serverId!==serverId)return reply.code(403).send({error:"server_identity_mismatch"});
  const q=await pool.query<{revision:string;state:Record<string,unknown>;saved_at:Date}>(
   "SELECT revision::text,state,saved_at FROM game_server_world_state WHERE server_id=$1",[serverId]);
  if(!q.rows[0])return{revision:0,state:{},savedAt:null};
  return{revision:Number(q.rows[0].revision),state:q.rows[0].state,savedAt:q.rows[0].saved_at};
 });

 app.put("/:serverId/world-state",{config:{rateLimit:{max:30,timeWindow:"1 minute"}}},async(req,reply)=>{
  const serverId=await serverFromRequest(req,reply);if(!serverId)return;
  const params=z.object({serverId:z.string().uuid()}).safeParse(req.params);
  const parsed=worldStateBody.safeParse(req.body);
  if(!params.success||!parsed.success)return reply.code(400).send({error:"invalid_world_state"});
  if(params.data.serverId!==serverId)return reply.code(403).send({error:"server_identity_mismatch"});
  const encoded=JSON.stringify(parsed.data.state);
  if(Buffer.byteLength(encoded,"utf8")>12000)return reply.code(413).send({error:"world_state_too_large"});
  const q=await pool.query<{revision:string}>(
   "INSERT INTO game_server_world_state(server_id,revision,state,saved_at) SELECT $1,1,$3::jsonb,now() WHERE $2=0 ON CONFLICT(server_id) DO UPDATE SET revision=game_server_world_state.revision+1,state=EXCLUDED.state,saved_at=now() WHERE game_server_world_state.revision=$2 RETURNING revision::text",
   [serverId,parsed.data.revision,encoded]);
  if(!q.rows[0]){
   const current=await pool.query<{revision:string}>("SELECT revision::text FROM game_server_world_state WHERE server_id=$1",[serverId]);
   return reply.code(409).send({error:"world_state_revision_conflict",currentRevision:Number(current.rows[0]?.revision??0)});
  }
  return{status:"saved",revision:Number(q.rows[0].revision)};
 });

};
