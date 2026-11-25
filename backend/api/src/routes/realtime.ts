import type {FastifyPluginAsync,FastifyRequest,FastifyReply} from "fastify";
import {z} from "zod";
import {pool} from "../db.js";
import {validateMovementProposal,validateRegionBounds,validateRegionProposal} from "../world/movement.js";
import {isReplayCursorValid} from "../world/event-cursor.js";
import {REGION_SPAWNS} from "../world/region-bounds.generated.js";
import {PlayerRealtimeLimits} from "../world/realtime-limits.js";

type Claims={playerId?:string;sub?:string;tokenVersion?:number};
type Socket=any;
const querySchema=z.object({lobbyId:z.string().uuid()});
const rooms=new Map<string,Set<Socket>>();
const realtimeLimits=new PlayerRealtimeLimits(2,30);
const MAX_QUEUED_MESSAGES_PER_SOCKET=30;
const playerPositions=new Map<string,{x:number;y:number;at:number}>();
const playerLastMessageAt=new Map<string,number>();
const positionSchema=z.object({type:z.literal("position"),regionId:z.string().trim().min(2).max(48).regex(/^[a-z0-9_]+$/),x:z.number().finite().min(-100000).max(100000),y:z.number().finite().min(-100000).max(100000)});
const emoteSchema=z.object({type:z.literal("emote"),emoteId:z.enum(["wave","cheer","sad","dance"])});
const ackSchema=z.object({type:z.literal("ack"),sequence:z.number().int().min(0).max(Number.MAX_SAFE_INTEGER)});
const resumeSchema=z.object({type:z.literal("resume"),lastSequence:z.number().int().min(0).max(Number.MAX_SAFE_INTEGER)});

function send(socket:Socket,payload:Record<string,unknown>):void{
 if(socket.readyState===1)socket.send(JSON.stringify(payload));
}
export function broadcast(lobbyId:string,payload:Record<string,unknown>):void{
 for(const socket of rooms.get(lobbyId)??[])send(socket,payload);
}
async function appendEvent(lobbyId:string,playerId:string,eventType:string,payload:Record<string,unknown>):Promise<number>{
 const q=await pool.query<{sequence:string}>(
  "WITH next_event AS (UPDATE co_op_lobbies SET next_event_sequence=next_event_sequence+1,updated_at=now() WHERE id=$1 AND status IN ('open','in_world') RETURNING next_event_sequence-1 AS sequence) INSERT INTO co_op_world_events(lobby_id,sequence,event_type,actor_player_id,payload) SELECT $1,next_event.sequence,$3,$2,$4::jsonb FROM next_event RETURNING sequence::text",
  [lobbyId,playerId,eventType,JSON.stringify(payload)]);
 if(!q.rows[0])throw new Error("lobby_not_active");
 return Number(q.rows[0].sequence);
}

export const realtimeRoutes:FastifyPluginAsync=async app=>{
 app.get("/realtime",{
  websocket:true,
  preValidation:async(request:FastifyRequest,reply:FastifyReply)=>{
   try{await request.jwtVerify();}catch{return reply.code(401).send({error:"authentication_required"});}
   const claims=request.user as Claims;
   if(!claims.sub||!Number.isInteger(claims.tokenVersion))return reply.code(401).send({error:"authentication_required"});
   const account=await pool.query<{token_version:number;status:string}>("SELECT token_version,status FROM accounts WHERE id=$1",[claims.sub]);
   if(account.rows[0]?.status!=="active"||account.rows[0].token_version!==claims.tokenVersion)return reply.code(401).send({error:"session_revoked"});
   const query=querySchema.safeParse(request.query);
   if(!query.success)return reply.code(400).send({error:"invalid_lobby_id"});
   const playerId=claims.playerId;
   if(!playerId)return reply.code(401).send({error:"authentication_required"});
   const membership=await pool.query("SELECT 1 FROM co_op_lobby_members m JOIN co_op_lobbies l ON l.id=m.lobby_id WHERE m.lobby_id=$1 AND m.player_id=$2 AND l.status IN ('open','in_world')",[query.data.lobbyId,playerId]);
   if(!membership.rowCount)return reply.code(403).send({error:"lobby_membership_required"});
  }
 },(socket:Socket,request:FastifyRequest)=>{
  const query=querySchema.parse(request.query);
  const lobbyId=query.lobbyId;
  const claims=request.user as Claims;
  const playerId=claims.playerId!;
  const accountId=claims.sub!;
  const tokenVersion=claims.tokenVersion!;
  const peers=rooms.get(lobbyId)??new Set<Socket>();
  if(!realtimeLimits.open(playerId)){
   send(socket,{type:"rejected",reason:"connection_limit"});
   socket.close(1008,"connection_limit");
   return;
  }
  peers.add(socket);rooms.set(lobbyId,peers);
  send(socket,{type:"connected",lobbyId,playerId});
  void pool.query("UPDATE player_presence SET state='in_world',last_heartbeat_at=now(),updated_at=now() WHERE player_id=$1",[playerId]).catch(()=>{});
  void pool.query(
   "SELECT p.id,p.name,p.level,m.role,l.region_id,l.next_event_sequence-1 AS last_sequence,latest.payload->>'x' AS x,latest.payload->>'y' AS y FROM co_op_lobby_members m JOIN players p ON p.id=m.player_id JOIN co_op_lobbies l ON l.id=m.lobby_id LEFT JOIN LATERAL (SELECT payload FROM co_op_world_events WHERE lobby_id=m.lobby_id AND actor_player_id=m.player_id AND event_type='position' ORDER BY sequence DESC LIMIT 1) latest ON true WHERE m.lobby_id=$1 ORDER BY m.joined_at",
   [lobbyId])
   .then(result=>{
    const now=Date.now();
    const regionId=String(result.rows[0]?.region_id??"");
    const spawn=REGION_SPAWNS[regionId];
    for(const member of result.rows){
     const x=member.x!==null?Number(member.x):spawn?.x;
     const y=member.y!==null?Number(member.y):spawn?.y;
     if(Number.isFinite(x)&&Number.isFinite(y)){
      member.x=x;member.y=y;
      const key=lobbyId+":"+member.id;
      playerPositions.set(key,{x:Number(x),y:Number(y),at:now});
     }
    }
    send(socket,{type:"snapshot",members:result.rows,sequence:Number(result.rows[0]?.last_sequence??0)});
   })
   .catch(error=>{
    request.log.error({err:error,lobbyId,playerId},"initial realtime snapshot unavailable");
    send(socket,{type:"error",code:"snapshot_unavailable"});
    socket.close(1011,"snapshot_unavailable");
   });

  let lobbyRegionId="";
  let queuedMessages=0;
  const lobbyRegionReady=pool.query<{region_id:string}>("SELECT region_id FROM co_op_lobbies WHERE id=$1 AND status IN ('open','in_world')",[lobbyId]).then(result=>{
   lobbyRegionId=result.rows[0]?.region_id??"";
   return lobbyRegionId.length>0;
  }).catch(error=>{
   request.log.warn({err:error,lobbyId},"lobby region lookup failed");
   return false;
  });

  let messageQueue:Promise<void>=Promise.resolve();
  socket.on("message",(raw:unknown)=>{
   if(queuedMessages>=MAX_QUEUED_MESSAGES_PER_SOCKET){
    send(socket,{type:"rejected",reason:"rate_limited"});
    return;
   }
   queuedMessages++;
   messageQueue=messageQueue.then(async()=>{
    if(socket.readyState!==1)return;
    const regionReady=await lobbyRegionReady;
    if(!regionReady){
     send(socket,{type:"error",code:"lobby_region_unavailable"});
     socket.close(1011,"lobby_region_unavailable");
     return;
    }
    let session:{rows:{token_version:number;status:string;is_member:boolean}[]};
    try{
     session=await pool.query<{token_version:number;status:string;is_member:boolean}>(
      "SELECT a.token_version,a.status,EXISTS(SELECT 1 FROM co_op_lobby_members m JOIN co_op_lobbies l ON l.id=m.lobby_id WHERE m.lobby_id=$2 AND m.player_id=$3 AND l.status IN ('open','in_world')) AS is_member FROM accounts a WHERE a.id=$1",
      [accountId,lobbyId,playerId]);
    }catch(error){
     request.log.error({err:error,lobbyId,playerId},"realtime session validation unavailable");
     send(socket,{type:"error",code:"session_validation_unavailable"});
     socket.close(1011,"session_validation_unavailable");
     return;
    }
    if(socket.readyState!==1)return;
    if(session.rows[0]?.status!=="active"||session.rows[0].token_version!==tokenVersion){send(socket,{type:"rejected",reason:"session_revoked"});socket.close(1008,"session_revoked");return;}
    if(!session.rows[0]?.is_member){send(socket,{type:"rejected",reason:"lobby_membership_required"});socket.close(1008,"lobby_membership_required");return;}
    const now=Date.now();
    if(!realtimeLimits.allowMessage(playerId,now)){
     send(socket,{type:"rejected",reason:"rate_limited"});
     return;
    }
    let message:unknown;
    try{message=JSON.parse(String(raw));}catch{send(socket,{type:"rejected",reason:"invalid_json"});return;}
    if(typeof message!=="object"||message===null){send(socket,{type:"rejected",reason:"invalid_message"});return;}
    const candidate=message as Record<string,unknown>;

    if(candidate.type==="ping"){
     if(socket.readyState!==1)return;
     await pool.query("UPDATE player_presence SET last_heartbeat_at=now(),updated_at=now() WHERE player_id=$1",[playerId]);
     send(socket,{type:"pong",serverTime:now});return;
    }
    const ack=ackSchema.safeParse(message);
    if(ack.success){
     if(socket.readyState!==1)return;
     const acknowledged=await pool.query<{last_ack_sequence:string}>(
      "UPDATE co_op_lobby_members SET last_ack_sequence=GREATEST(last_ack_sequence,LEAST($3,(SELECT next_event_sequence-1 FROM co_op_lobbies WHERE id=$1))) WHERE lobby_id=$1 AND player_id=$2 RETURNING last_ack_sequence::text",
      [lobbyId,playerId,ack.data.sequence]);
     if(!acknowledged.rows[0]){send(socket,{type:"rejected",reason:"lobby_membership_required"});return;}
     send(socket,{type:"acknowledged",sequence:Number(acknowledged.rows[0].last_ack_sequence)});return;
    }
    const resume=resumeSchema.safeParse(message);
    if(resume.success){
     const cursor=await pool.query<{latest_sequence:string}>("SELECT (next_event_sequence-1)::text AS latest_sequence FROM co_op_lobbies WHERE id=$1 AND status IN ('open','in_world')",[lobbyId]);
     const latestSequence=Number(cursor.rows[0]?.latest_sequence??0);
     if(!isReplayCursorValid(resume.data.lastSequence,latestSequence)){send(socket,{type:"rejected",reason:"future_sequence",latestSequence});return;}
     const events=await pool.query("SELECT sequence,event_type,actor_player_id,payload FROM co_op_world_events WHERE lobby_id=$1 AND sequence>$2 ORDER BY sequence LIMIT 201",[lobbyId,resume.data.lastSequence]);
     if(events.rows.length>0&&events.rows.length<=200)send(socket,{type:"replay",events:events.rows});
     else if(events.rows.length>200){
      const snapshot=await pool.query(
       "SELECT p.id,p.name,p.level,m.role,l.region_id,l.next_event_sequence-1 AS last_sequence,latest.payload->>'x' AS x,latest.payload->>'y' AS y FROM co_op_lobby_members m JOIN players p ON p.id=m.player_id JOIN co_op_lobbies l ON l.id=m.lobby_id LEFT JOIN LATERAL (SELECT payload FROM co_op_world_events WHERE lobby_id=m.lobby_id AND actor_player_id=m.player_id AND event_type='position' ORDER BY sequence DESC LIMIT 1) latest ON true WHERE m.lobby_id=$1 ORDER BY m.joined_at",
       [lobbyId]);
      const regionId=String(snapshot.rows[0]?.region_id??lobbyRegionId);
      const spawn=REGION_SPAWNS[regionId];
      const snapshotAt=Date.now();
      for(const member of snapshot.rows){
       const x=member.x!==null?Number(member.x):spawn?.x;
       const y=member.y!==null?Number(member.y):spawn?.y;
       if(Number.isFinite(x)&&Number.isFinite(y)){member.x=x;member.y=y;playerPositions.set(lobbyId+":"+member.id,{x:Number(x),y:Number(y),at:snapshotAt});}
      }
      send(socket,{type:"snapshot",members:snapshot.rows,sequence:Number(snapshot.rows[0]?.last_sequence??0),requires_resync:true});
     }else send(socket,{type:"replay",events:[]});
     return;
    }
    const position=positionSchema.safeParse(message);
    if(position.success){
     if(!validateRegionProposal(lobbyRegionId,position.data.regionId)){
      send(socket,{type:"rejected",reason:lobbyRegionId?"region_mismatch":"lobby_region_unavailable"});return;
     }
     if(!validateRegionBounds(lobbyRegionId,position.data)){
      send(socket,{type:"rejected",reason:"region_bounds"});return;
     }
     const movementKey=lobbyId+":"+playerId;
     const previousMessageAt=playerLastMessageAt.get(movementKey)??0;
     if(now-previousMessageAt<25){send(socket,{type:"rejected",reason:"position_rate_limited"});return;}
     const previousPosition=playerPositions.get(movementKey)??null;
     const elapsed=previousPosition?(now-previousPosition.at)/1000:0;
     const validation=validateMovementProposal(previousPosition,position.data,elapsed);
     if(!validation.ok){send(socket,{type:"rejected",reason:validation.reason});return;}
     if(socket.readyState!==1)return;
     const event={type:"position",playerId,x:position.data.x,y:position.data.y};
     const sequence=await appendEvent(lobbyId,playerId,"position",{x:position.data.x,y:position.data.y});
     playerPositions.set(movementKey,{x:position.data.x,y:position.data.y,at:now});
     playerLastMessageAt.set(movementKey,now);
     broadcast(lobbyId,{...event,sequence});return;
    }
    const emote=emoteSchema.safeParse(message);
    if(emote.success){
     if(socket.readyState!==1)return;
     const sequence=await appendEvent(lobbyId,playerId,"emote",{emoteId:emote.data.emoteId});
     broadcast(lobbyId,{type:"emote",playerId,emoteId:emote.data.emoteId,sequence});return;
    }
    send(socket,{type:"rejected",reason:"unsupported_event"});
   }).catch(error=>{request.log.warn({err:error,lobbyId,playerId},"realtime event rejected");send(socket,{type:"error",code:"event_failed"});}).finally(()=>{queuedMessages=Math.max(0,queuedMessages-1);});
  });

  socket.on("close",()=>{
   peers.delete(socket);
   if(peers.size===0)rooms.delete(lobbyId);
   realtimeLimits.close(playerId);
   if(realtimeLimits.connectionCount(playerId)===0){
    const movementKey=lobbyId+":"+playerId;
    playerPositions.delete(movementKey);
    playerLastMessageAt.delete(movementKey);
    void pool.query(
     "UPDATE player_presence SET state=CASE WHEN EXISTS(SELECT 1 FROM co_op_lobby_members WHERE player_id=$1) THEN 'in_lobby' ELSE 'online' END,last_heartbeat_at=now(),updated_at=now() WHERE player_id=$1",
     [playerId]
    ).catch(error=>request.log.warn({err:error,playerId},"presence cleanup failed"));
   }
  });
 });
};
