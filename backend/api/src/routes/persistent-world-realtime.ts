import {titleName,verifiedTitleSql} from "./daily-quests.js";
import type {FastifyPluginAsync,FastifyRequest,FastifyReply} from "fastify";
import {createHash,randomUUID} from "node:crypto";
import {z} from "zod";
import {pool} from "../db.js";
import {validateRegionBounds} from "../world/movement.js";
import {canReplayFromCursor,hasContiguousEventSequences} from "../world/persistent-replay-window.js";
import {shouldSendWorldSyncHint} from "../world/persistent-sync-hint.js";

type Claims={playerId?:string;sub?:string;tokenVersion?:number};
type Socket=any;
type Peer={socket:Socket;playerId:string;accountId:string;tokenVersion:number;connectionId:string;ready:boolean;replaying:boolean;pendingEvents:Array<Record<string,unknown>>;admissionTimer?:ReturnType<typeof setTimeout>;leaseTimer?:ReturnType<typeof setInterval>};
const querySchema=z.object({serverId:z.string().uuid()});
const ticketSchema=z.object({type:z.literal("join_ticket"),ticket:z.string().min(40).max(200),lastEventSequence:z.number().int().nonnegative().max(Number.MAX_SAFE_INTEGER).default(0)});
const positionSchema=z.object({type:z.literal("position"),x:z.number().finite().min(-100000).max(100000),y:z.number().finite().min(-100000).max(100000)});
const emoteSchema=z.object({type:z.literal("emote"),emoteId:z.enum(["wave","cheer","sad","dance"])});
const rooms=new Map<string,Set<Peer>>();
const positions=new Map<string,{x:number;y:number;at:number}>();
const lastPositionMessageAt=new Map<string,number>();
const disconnectGraceTimers=new Map<string,ReturnType<typeof setTimeout>>();
const instanceId=randomUUID();
const WORLD_EVENT_CHANNEL="reverie_world_events";
const DISCONNECT_GRACE_MS=15000;
const digest=(value:string)=>createHash("sha256").update(value).digest("hex");
async function appendWorldEvent(serverId:string,playerId:string|null,eventType:"position"|"emote"|"player_joined"|"player_left",payload:Record<string,unknown>):Promise<number>{
 const encoded=JSON.stringify(payload);
 const result=await pool.query<{sequence:string}>(
  "WITH bumped AS (UPDATE game_servers SET next_event_sequence=next_event_sequence+1,updated_at=now() WHERE id=$1 RETURNING next_event_sequence), inserted AS (INSERT INTO game_server_world_events(server_id,sequence,event_type,player_id,payload) SELECT $1,next_event_sequence,$3,$2,$4::jsonb FROM bumped RETURNING sequence) SELECT sequence::text FROM inserted",
  [serverId,playerId,eventType,encoded]);
 if(!result.rows[0])throw new Error("world_event_server_missing");
 return Number(result.rows[0].sequence);
}
function send(peer:Peer,payload:Record<string,unknown>):void{
 if(peer.socket.readyState===1)peer.socket.send(JSON.stringify(payload));
}
function deliverLocal(serverId:string,payload:Record<string,unknown>,except?:Peer):void{
 for(const peer of rooms.get(serverId)??[]){
  if(peer===except||!peer.ready)continue;
  if(peer.replaying){
   if(peer.pendingEvents.length<200)peer.pendingEvents.push(payload);
   else{send(peer,{type:"world_resync_required",reason:"replay_queue_overflow"});peer.socket.close(1012,"world_resync_required");}
  }else send(peer,payload);
 }
}
function broadcast(serverId:string,payload:Record<string,unknown>,except?:Peer):void{
 deliverLocal(serverId,payload,except);
 // PostgreSQL NOTIFY fans the committed event out to every API process. The
 // origin ID prevents the LISTEN connection in this process echoing it locally.
 void pool.query("SELECT pg_notify($1,$2)",[WORLD_EVENT_CHANNEL,JSON.stringify({serverId,payload,origin:instanceId})])
  .catch(error=>console.error({event:"world_event_publish_failed",serverId,message:error instanceof Error?error.message:"unknown"}));
}
export const persistentWorldRealtimeRoutes:FastifyPluginAsync=async app=>{
 // A dedicated connection keeps LISTEN active independently of request traffic.
 // If the subscription cannot be established, fail startup rather than silently
 // running a multi-instance deployment with process-local broadcasts only.
 const listener=await pool.connect();
 try{
  listener.on("notification",message=>{
   if(message.channel!==WORLD_EVENT_CHANNEL||!message.payload)return;
   try{
    const event=JSON.parse(message.payload) as {serverId?:string;payload?:Record<string,unknown>;origin?:string};
    if(event.origin!==instanceId&&event.serverId&&event.payload&&typeof event.payload==="object")
     deliverLocal(event.serverId,event.payload);
   }catch(error){app.log.warn({err:error},"invalid persistent world notification ignored");}
  });
  listener.on("error",error=>{
   app.log.fatal({err:error},"persistent world notification listener failed; stopping this API instance to avoid split-brain world delivery");
   void app.close().catch(closeError=>app.log.error({err:closeError},"API shutdown after notification listener failure failed"));
  });
  await listener.query("LISTEN "+WORLD_EVENT_CHANNEL);
 }catch(error){listener.release(true);throw error;}
 app.addHook("onClose",async()=>listener.release());
 app.get("/world/realtime",{
  websocket:true,
  preValidation:async(request:FastifyRequest,reply:FastifyReply)=>{
   try{await request.jwtVerify();}catch{return reply.code(401).send({error:"authentication_required"});}
   const claims=request.user as Claims;
   if(!claims.sub||!claims.playerId||!Number.isInteger(claims.tokenVersion))return reply.code(401).send({error:"authentication_required"});
   const query=querySchema.safeParse(request.query);
   if(!query.success)return reply.code(400).send({error:"invalid_server_id"});
   const account=await pool.query<{token_version:number;status:string}>("SELECT token_version,status FROM accounts WHERE id=$1",[claims.sub]);
   if(account.rows[0]?.status!=="active"||account.rows[0].token_version!==claims.tokenVersion)return reply.code(401).send({error:"session_revoked"});
   const assignment=await pool.query<{region_id:string}>("SELECT s.region_id FROM game_server_players p JOIN game_servers s ON s.id=p.server_id WHERE p.server_id=$1 AND p.player_id=$2 AND s.status IN('online','draining') AND s.heartbeat_at>now()-interval '60 seconds'",[query.data.serverId,claims.playerId]);
   if(!assignment.rowCount)return reply.code(403).send({error:"server_assignment_required"});
   if(["story_training_ground","story_village","story_royal_gardens","story_royal_gate"].includes(assignment.rows[0]!.region_id))return reply.code(403).send({error:"dedicated_story_transport_required"});
  }
 },(socket:Socket,request:FastifyRequest)=>{
  const {serverId}=querySchema.parse(request.query);
  const claims=request.user as Claims;
  const peer:Peer={socket,playerId:claims.playerId!,accountId:claims.sub!,tokenVersion:claims.tokenVersion!,connectionId:randomUUID(),ready:false,replaying:false,pendingEvents:[]};
  const peers=rooms.get(serverId)??new Set<Peer>();
  if([...peers].filter(p=>p.playerId===peer.playerId).length>=2){send(peer,{type:"rejected",reason:"connection_limit"});socket.close(1008,"connection_limit");return;}
  peers.add(peer);rooms.set(serverId,peers);
  // Do not let an unauthenticated socket hold a reserved player assignment indefinitely.
  peer.admissionTimer=setTimeout(()=>{
   if(!peer.ready&&peer.socket.readyState===1)peer.socket.close(1008,"join_ticket_timeout");
  },10000);
  let queue:Promise<void>=Promise.resolve();
  let queued=0;
  send(peer,{type:"ticket_required",serverId});
  socket.on("message",(raw:unknown)=>{
   if(queued>=20){send(peer,{type:"rejected",reason:"rate_limited"});return;}
   queued++;
   queue=queue.then(async()=>{
    if(socket.readyState!==1)return;
    let message:unknown;
    try{message=JSON.parse(String(raw));}catch{send(peer,{type:"rejected",reason:"invalid_json"});return;}
    if(!peer.ready){
     const ticket=ticketSchema.safeParse(message);
     if(!ticket.success){send(peer,{type:"rejected",reason:"join_ticket_required"});socket.close(1008,"join_ticket_required");return;}
     const client=await pool.connect();
     try{
      await client.query("BEGIN");
      const session=await client.query<{token_version:number;status:string}>("SELECT token_version,status FROM accounts WHERE id=$1 FOR SHARE",[peer.accountId]);
      if(session.rows[0]?.status!=="active"||session.rows[0].token_version!==peer.tokenVersion){await client.query("ROLLBACK");send(peer,{type:"rejected",reason:"session_revoked"});socket.close(1008,"session_revoked");return;}
      const redeemed=await client.query<{player_id:string}>(
       "SELECT t.player_id FROM game_server_join_tickets t JOIN game_server_players p ON p.server_id=t.server_id AND p.player_id=t.player_id JOIN game_servers s ON s.id=t.server_id WHERE t.server_id=$1 AND t.player_id=$2 AND t.ticket_hash=$3 AND t.consumed_at IS NULL AND t.expires_at>now() AND s.status IN('online','draining') AND s.heartbeat_at>now()-interval '60 seconds' FOR UPDATE OF t",
       [serverId,peer.playerId,digest(ticket.data.ticket)]);
      if(!redeemed.rowCount){await client.query("ROLLBACK");send(peer,{type:"rejected",reason:"join_ticket_invalid_or_expired"});socket.close(1008,"invalid_join_ticket");return;}
      const assignment=await client.query("SELECT 1 FROM game_server_players WHERE server_id=$1 AND player_id=$2 FOR UPDATE",[serverId,peer.playerId]);
      if(!assignment.rowCount){await client.query("ROLLBACK");send(peer,{type:"rejected",reason:"server_assignment_required"});socket.close(1008,"server_assignment_required");return;}
      await client.query("DELETE FROM game_server_player_connections WHERE server_id=$1 AND player_id=$2 AND lease_expires_at<=now()",[serverId,peer.playerId]);
      const activeConnections=await client.query<{count:string}>("SELECT count(*)::text AS count FROM game_server_player_connections WHERE server_id=$1 AND player_id=$2 AND lease_expires_at>now()",[serverId,peer.playerId]);
      if(Number(activeConnections.rows[0]?.count??0)>=2){await client.query("ROLLBACK");send(peer,{type:"rejected",reason:"connection_limit"});socket.close(1008,"connection_limit");return;}
      await client.query("INSERT INTO game_server_player_connections(connection_id,server_id,player_id,lease_expires_at) VALUES($1,$2,$3,now()+interval '45 seconds')",[peer.connectionId,serverId,peer.playerId]);
      await client.query("UPDATE game_server_join_tickets SET consumed_at=now() WHERE server_id=$1 AND player_id=$2 AND ticket_hash=$3",[serverId,peer.playerId,digest(ticket.data.ticket)]);
      await client.query("UPDATE game_server_players SET last_seen_at=now() WHERE server_id=$1 AND player_id=$2",[serverId,peer.playerId]);
      await client.query("COMMIT");
     }catch(error){await client.query("ROLLBACK");request.log.error({err:error,serverId},"world join ticket redemption failed");send(peer,{type:"error",code:"ticket_validation_unavailable"});socket.close(1011,"ticket_validation_unavailable");return;}
     finally{client.release();}
     if(peer.admissionTimer){clearTimeout(peer.admissionTimer);peer.admissionTimer=undefined;}
     peer.leaseTimer=setInterval(()=>{
      void pool.query("UPDATE game_server_player_connections SET lease_expires_at=now()+interval '45 seconds' WHERE connection_id=$1 AND server_id=$2 AND player_id=$3 AND EXISTS(SELECT 1 FROM accounts WHERE id=$4 AND status='active' AND token_version=$5) RETURNING connection_id",[peer.connectionId,serverId,peer.playerId,peer.accountId,peer.tokenVersion]).then(result=>{
       if(!result.rowCount&&peer.socket.readyState===1)peer.socket.close(1011,"connection_lease_lost");
      }).catch(error=>{
       request.log.error({err:error,serverId,playerId:peer.playerId},"persistent world connection lease renewal failed");
       if(peer.socket.readyState===1)peer.socket.close(1011,"connection_lease_unavailable");
      });
     },15000);
     peer.leaseTimer.unref();
     const playerKey=serverId+":"+peer.playerId;
     const reconnectTimer=disconnectGraceTimers.get(playerKey);
     if(reconnectTimer){clearTimeout(reconnectTimer);disconnectGraceTimers.delete(playerKey);}
     // Ticket redemption is the admission boundary: from here onward a close must
     // schedule normal disconnect cleanup, including while the snapshot is loading.
     peer.ready=true;
     peer.replaying=true;
     peer.pendingEvents=[];
     if(socket.readyState!==1)return;
     // Lock the server sequence row while taking the snapshot. Every world-event
     // append updates this same row, so the snapshot and cursor share one boundary.
     const snapshotClient=await pool.connect();
     let stateRows:{revision:string;state:Record<string,unknown>}[]=[];
     let memberRows:{player_id:string;name:string;level:number;title_id:string;x:number|null;y:number|null;position_updated_at:Date|null}[]=[];
     let joinSequence=0;
     try{
      await snapshotClient.query("BEGIN");
      await snapshotClient.query("SELECT id FROM game_servers WHERE id=$1 FOR UPDATE",[serverId]);
      const state=await snapshotClient.query<{revision:string;state:Record<string,unknown>}>("SELECT revision::text,state FROM game_server_world_state WHERE server_id=$1",[serverId]);
      const members=await snapshotClient.query<{player_id:string;name:string;level:number;title_id:string;x:number|null;y:number|null;position_updated_at:Date|null}>("SELECT p.id AS player_id,p.name,p.level,"+verifiedTitleSql+" AS title_id,ps.x,ps.y,ps.updated_at AS position_updated_at FROM game_server_players a JOIN players p ON p.id=a.player_id LEFT JOIN game_server_player_state ps ON ps.server_id=a.server_id AND ps.player_id=a.player_id WHERE a.server_id=$1 ORDER BY a.joined_at",[serverId]);
      const event=await snapshotClient.query<{sequence:string}>("WITH bumped AS (UPDATE game_servers SET next_event_sequence=next_event_sequence+1,updated_at=now() WHERE id=$1 RETURNING next_event_sequence), inserted AS (INSERT INTO game_server_world_events(server_id,sequence,event_type,player_id,payload) SELECT $1,next_event_sequence,'player_joined',$2,'{}'::jsonb FROM bumped RETURNING sequence) SELECT sequence::text FROM inserted",[serverId,peer.playerId]);
      if(!event.rows[0])throw new Error("world_event_server_missing");
      joinSequence=Number(event.rows[0].sequence);
      stateRows=state.rows;
      memberRows=members.rows;
      await snapshotClient.query("COMMIT");
     }catch(error){
      await snapshotClient.query("ROLLBACK").catch(()=>{});
      throw error;
     }finally{snapshotClient.release();}
     const snapshotMembers=memberRows.map(member=>{
      if(member.x!==null&&member.y!==null)positions.set(serverId+":"+member.player_id,{x:member.x,y:member.y,at:member.position_updated_at?.getTime()??Date.now()});
      return{playerId:member.player_id,name:member.name,level:member.level,title:titleName(member.title_id),x:member.x,y:member.y};
     });
     if(socket.readyState!==1)return;
     // This is an authoritative snapshot, not a historical replay. Its cursor is
     // the exact sequence committed with the snapshot; later live events are queued.
     send(peer,{type:"world_joined",serverId,playerId:peer.playerId,revision:Number(stateRows[0]?.revision??0),eventSequence:joinSequence,currentEventSequence:joinSequence,replayAvailable:false,worldState:stateRows[0]?.state??{},members:snapshotMembers});
     const queuedEvents=peer.pendingEvents.splice(0).sort((a,b)=>Number(a.sequence??0)-Number(b.sequence??0));
     peer.replaying=false;
     for(const event of queuedEvents)send(peer,event);
     const joined=snapshotMembers.find(m=>m.playerId===peer.playerId);
     broadcast(serverId,{type:"player_joined",playerId:peer.playerId,name:joined?.name??"Wanderer",title:joined?.title??"",sequence:joinSequence},peer);
     return;
    }
    const account=await pool.query<{token_version:number;status:string}>("SELECT token_version,status FROM accounts WHERE id=$1",[peer.accountId]);
    if(account.rows[0]?.status!=="active"||account.rows[0].token_version!==peer.tokenVersion){send(peer,{type:"rejected",reason:"session_revoked"});socket.close(1008,"session_revoked");return;}
    if(typeof message!=="object"||message===null){send(peer,{type:"rejected",reason:"invalid_message"});return;}
    const position=positionSchema.safeParse(message);
    if(position.success){
     const region=await pool.query<{region_id:string}>("SELECT region_id FROM game_servers WHERE id=$1",[serverId]);
     if(!region.rows[0]||!validateRegionBounds(region.rows[0].region_id,{x:position.data.x,y:position.data.y})){
      send(peer,{type:"rejected",reason:"region_bounds"});return;
     }
     const key=serverId+":"+peer.playerId;
     const now=Date.now();
     const previousMessageAt=lastPositionMessageAt.get(key)??0;
     if(now-previousMessageAt<25){send(peer,{type:"rejected",reason:"position_rate_limited"});return;}
     const previous=positions.get(key);
     if(previous&&Math.hypot(position.data.x-previous.x,position.data.y-previous.y)>120){send(peer,{type:"rejected",reason:"movement_too_fast"});return;}
     const client=await pool.connect();
     let sequence:number;
     try{
      await client.query("BEGIN");
      await client.query("SELECT id FROM game_servers WHERE id=$1 FOR UPDATE",[serverId]);
      const saved=await client.query("INSERT INTO game_server_player_state(server_id,player_id,x,y,updated_at) SELECT $1,$2,$3,$4,now() WHERE EXISTS(SELECT 1 FROM game_server_players WHERE server_id=$1 AND player_id=$2) ON CONFLICT(server_id,player_id) DO UPDATE SET x=EXCLUDED.x,y=EXCLUDED.y,updated_at=now() RETURNING player_id",[serverId,peer.playerId,position.data.x,position.data.y]);
      if(!saved.rowCount){await client.query("ROLLBACK");send(peer,{type:"rejected",reason:"server_assignment_required"});socket.close(1008,"server_assignment_required");return;}
      const event=await client.query<{sequence:string}>("WITH bumped AS (UPDATE game_servers SET next_event_sequence=next_event_sequence+1,updated_at=now() WHERE id=$1 RETURNING next_event_sequence), inserted AS (INSERT INTO game_server_world_events(server_id,sequence,event_type,player_id,payload) SELECT $1,next_event_sequence,'position',$2,$3::jsonb FROM bumped RETURNING sequence) SELECT sequence::text FROM inserted",[serverId,peer.playerId,JSON.stringify({x:position.data.x,y:position.data.y})]);
      if(!event.rows[0])throw new Error("world_event_server_missing");
      sequence=Number(event.rows[0].sequence);
      await client.query("COMMIT");
     }catch(error){
      await client.query("ROLLBACK").catch(()=>{});
      throw error;
     }finally{client.release();}
     positions.set(key,{x:position.data.x,y:position.data.y,at:now});
     lastPositionMessageAt.set(key,now);
     broadcast(serverId,{type:"position",playerId:peer.playerId,x:position.data.x,y:position.data.y,sequence});
     return;
    }
    const emote=emoteSchema.safeParse(message);
    if(emote.success){const sequence=await appendWorldEvent(serverId,peer.playerId,"emote",{emoteId:emote.data.emoteId});broadcast(serverId,{type:"emote",playerId:peer.playerId,emoteId:emote.data.emoteId,sequence});return;}
    if((message as Record<string,unknown>).type==="replay_request"){
     const cursor=z.number().int().nonnegative().max(Number.MAX_SAFE_INTEGER).safeParse((message as Record<string,unknown>).lastSequence);
     if(!cursor.success){send(peer,{type:"rejected",reason:"invalid_replay_cursor"});return;}
     peer.replaying=true;peer.pendingEvents=[];
     const replayWindow=await pool.query<{min_sequence:string|null;current_sequence:string}>("SELECT (SELECT min(sequence)::text FROM game_server_world_events WHERE server_id=$1) AS min_sequence,next_event_sequence::text AS current_sequence FROM game_servers WHERE id=$1",[serverId]);
     const oldestSequence=replayWindow.rows[0]?.min_sequence===null?null:Number(replayWindow.rows[0]?.min_sequence);
     const currentSequence=Number(replayWindow.rows[0]?.current_sequence??0);
     const events=await pool.query<{sequence:string;event_type:string;player_id:string|null;payload:Record<string,unknown>}>("SELECT sequence::text,event_type,player_id,payload FROM game_server_world_events WHERE server_id=$1 AND sequence>$2 AND sequence<=$3 ORDER BY sequence ASC LIMIT 201",[serverId,cursor.data,currentSequence]);
     if(!canReplayFromCursor(cursor.data,oldestSequence,currentSequence,events.rows.length)||!hasContiguousEventSequences(cursor.data,currentSequence,events.rows.map(event=>Number(event.sequence)))){send(peer,{type:"world_resync_required",reason:"replay_window_unavailable"});peer.socket.close(1012,"world_resync_required");return;}
     for(const event of events.rows)send(peer,{type:event.event_type,playerId:event.player_id,sequence:Number(event.sequence),...event.payload});
     const queuedEvents=peer.pendingEvents.splice(0).sort((a,b)=>Number(a.sequence??0)-Number(b.sequence??0));
     peer.replaying=false;
     for(const event of queuedEvents)send(peer,event);
     send(peer,{type:"replay_complete",lastSequence:events.rows.length?Number(events.rows[events.rows.length-1]!.sequence):cursor.data});
     return;
    }
    if((message as Record<string,unknown>).type==="ping"){
     const lastSequence=z.number().int().nonnegative().max(Number.MAX_SAFE_INTEGER).safeParse((message as Record<string,unknown>).lastSequence??0);
     if(!lastSequence.success){send(peer,{type:"rejected",reason:"invalid_event_cursor"});return;}
     const cursor=await pool.query<{current_sequence:string}>("SELECT next_event_sequence::text AS current_sequence FROM game_servers WHERE id=$1",[serverId]);
     const currentSequence=Number(cursor.rows[0]?.current_sequence??0);
     if(shouldSendWorldSyncHint(lastSequence.data,currentSequence))send(peer,{type:"world_sync_hint",currentSequence});
     const titles=await pool.query("SELECT p.id AS \"playerId\","+verifiedTitleSql+" AS title_id FROM game_server_players m JOIN players p ON p.id=m.player_id WHERE m.server_id=$1",[serverId]);
      send(peer,{type:"player_titles",players:titles.rows.map(r=>({playerId:r.playerId,title:titleName(r.title_id)}))});
      send(peer,{type:"pong",serverTime:Date.now()});
     return;
    }
    send(peer,{type:"rejected",reason:"unsupported_event"});
   }).catch(error=>{
    request.log.error({err:error,serverId},"persistent world message failed");
    if(peer.replaying){
     peer.replaying=false;
     peer.pendingEvents=[];
     if(socket.readyState===1)socket.close(1011,"world_sync_failed");
    }
    send(peer,{type:"error",code:"world_message_failed"});
   }).finally(()=>{queued=Math.max(0,queued-1);});
  });
  socket.on("close",()=>{
   if(peer.admissionTimer){clearTimeout(peer.admissionTimer);peer.admissionTimer=undefined;}
   if(peer.leaseTimer){clearInterval(peer.leaseTimer);peer.leaseTimer=undefined;}
   peers.delete(peer);if(peers.size===0)rooms.delete(serverId);
   if(peer.ready)void pool.query("DELETE FROM game_server_player_connections WHERE connection_id=$1",[peer.connectionId]).catch(error=>request.log.error({err:error,serverId,playerId:peer.playerId},"persistent world connection lease release failed"));
   if(!peer.ready)return;
   const playerKey=serverId+":"+peer.playerId;
   const previousTimer=disconnectGraceTimers.get(playerKey);
   if(previousTimer)clearTimeout(previousTimer);
   const scheduleCleanup=():void=>{
    const timer=setTimeout(()=>{
     // Database leases and outstanding one-time tickets are authoritative across
     // API processes; the local rooms map is only an in-process broadcast cache.
     disconnectGraceTimers.delete(playerKey);
     positions.delete(playerKey);
     lastPositionMessageAt.delete(playerKey);
     void (async()=>{
      const retryCleanup=():void=>{
       const retry=setTimeout(()=>scheduleCleanup(),5000);
       disconnectGraceTimers.set(playerKey,retry);
      };
      let client;
      try{
       client=await pool.connect();
       try{
        await client.query("BEGIN");
        await client.query("SELECT id FROM game_servers WHERE id=$1 FOR UPDATE",[serverId]);
        const assignment=await client.query("SELECT 1 FROM game_server_players WHERE server_id=$1 AND player_id=$2 FOR UPDATE",[serverId,peer.playerId]);
        if(!assignment.rowCount){await client.query("COMMIT");return;}
        const presence=await client.query<{active:boolean}>("SELECT EXISTS(SELECT 1 FROM game_server_player_connections WHERE server_id=$1 AND player_id=$2 AND lease_expires_at>now()) OR EXISTS(SELECT 1 FROM game_server_join_tickets WHERE server_id=$1 AND player_id=$2 AND consumed_at IS NULL AND expires_at>now()) AS active",[serverId,peer.playerId]);
        if(presence.rows[0]?.active){await client.query("COMMIT");retryCleanup();return;}
        await client.query("UPDATE game_server_join_tickets SET consumed_at=now() WHERE server_id=$1 AND player_id=$2 AND consumed_at IS NULL",[serverId,peer.playerId]);
        await client.query("DELETE FROM game_server_player_state WHERE server_id=$1 AND player_id=$2",[serverId,peer.playerId]);
        await client.query("DELETE FROM game_server_players WHERE server_id=$1 AND player_id=$2",[serverId,peer.playerId]);
        const event=await client.query<{sequence:string}>("WITH bumped AS (UPDATE game_servers SET next_event_sequence=next_event_sequence+1,updated_at=now() WHERE id=$1 RETURNING next_event_sequence), inserted AS (INSERT INTO game_server_world_events(server_id,sequence,event_type,player_id,payload) SELECT $1,next_event_sequence,'player_left',$2,'{}'::jsonb FROM bumped RETURNING sequence) SELECT sequence::text FROM inserted",[serverId,peer.playerId]);
        if(!event.rows[0])throw new Error("world_event_server_missing");
        const sequence=Number(event.rows[0].sequence);
        await client.query("COMMIT");
        broadcast(serverId,{type:"player_left",playerId:peer.playerId,sequence});
       }catch(error){
        await client.query("ROLLBACK").catch(rollbackError=>request.log.error({err:rollbackError,serverId,playerId:peer.playerId},"persistent world disconnect rollback failed"));
        throw error;
       }finally{client.release();}
      }catch(error){
       request.log.error({err:error,serverId,playerId:peer.playerId},"persistent world disconnect cleanup failed");
       // A transient database failure must not strand the player's server slot.
       retryCleanup();
      }
     })();
    },DISCONNECT_GRACE_MS);
    disconnectGraceTimers.set(playerKey,timer);
   };
   scheduleCleanup();
  });
 });
};
