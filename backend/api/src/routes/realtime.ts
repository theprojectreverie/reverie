import type {FastifyPluginAsync,FastifyRequest,FastifyReply} from "fastify";
import {z} from "zod";
import {pool} from "../db.js";
import {grantPartyXp} from "../world/character-xp.js";
import {recordOnlineDailyVictory,titleName,verifiedTitleSql} from "./daily-quests.js";
import {validateMovementProposal,validateRegionBounds,validateRegionProposal} from "../world/movement.js";
import {isReplayCursorValid} from "../world/event-cursor.js";
import {REGION_SPAWNS,EXPEDITION_PORTALS} from "../world/region-bounds.generated.js";
import {PlayerRealtimeLimits} from "../world/realtime-limits.js";
import {cassienSpecial} from "../world/cassien-special.js";

type Claims={playerId?:string;sub?:string;tokenVersion?:number};
type Socket=any;
const querySchema=z.object({lobbyId:z.string().uuid()});
const rooms=new Map<string,Set<Socket>>();
const socketPlayers=new WeakMap<object,string>();
// Explicit leave immediately revokes that member's subscriptions, even if idle.
export function revokeLobbyMember(lobbyId:string,playerId:string):void{
 const peers=rooms.get(lobbyId);
 for(const socket of peers??[]){
  if(socketPlayers.get(socket)!==playerId)continue;
  peers!.delete(socket);
  send(socket,{type:"rejected",reason:"lobby_membership_required"});
  socket.close(1008,"lobby_membership_required");
 }
 const key=lobbyId+":"+playerId;
 playerPositions.delete(key);playerLastMessageAt.delete(key);
}
const realtimeLimits=new PlayerRealtimeLimits(2,30);
const MAX_QUEUED_MESSAGES_PER_SOCKET=30;
const playerPositions=new Map<string,{x:number;y:number;at:number}>();
const playerLastMessageAt=new Map<string,number>();
const positionSchema=z.object({type:z.literal("position"),regionId:z.string().trim().min(2).max(48).regex(/^[a-z0-9_]+$/),x:z.number().finite().min(-100000).max(100000),y:z.number().finite().min(-100000).max(100000)});
const emoteSchema=z.object({type:z.literal("emote"),emoteId:z.enum(["wave","cheer","sad","dance"])});
const ackSchema=z.object({type:z.literal("ack"),sequence:z.number().int().min(0).max(Number.MAX_SAFE_INTEGER)});
const resumeSchema=z.object({type:z.literal("resume"),lastSequence:z.number().int().min(0).max(Number.MAX_SAFE_INTEGER)});

// Fixed authored Royal Gardens spawn points. Cooperative combat initially uses
// stationary targets; all damage and defeat timing are server-owned.
const gardenMonsters: Record<string,[number,number]> = {
 rose_slime_garden_1:[-1100,2200],rose_slime_garden_2:[-800,1850],rose_slime_garden_3:[-1450,1500],rose_slime_garden_4:[700,2250],rose_slime_garden_5:[1200,1750],rose_slime_garden_6:[950,1000],crownling_garden_1:[-900,2100],crownling_garden_2:[550,2100],crownling_garden_3:[1100,1500]
};
const gateMonsters:Record<string,[number,number]>={royal_gate_patrol_1:[-65,1200],royal_gate_patrol_2:[75,1840]};
const willowMonsters:Record<string,[number,number]>={willow_slime_1:[-2350,1370]};
const worldMonsters={...gardenMonsters,...gateMonsters,...willowMonsters};
function monstersForRegion(region:string):Record<string,[number,number]>{
 return region==="six_zone_royal_gardens"?gardenMonsters:region==="six_zone_royal_gate"?gateMonsters:region==="six_zone_willow_fields"?willowMonsters:{};
}
function monsterMaxHp(id:string):number{return Object.hasOwn(gateMonsters,id)?120:100;}
// Small server-clock-driven patrols around the authored, collision-safe spawn areas.
// The same position function is used for presentation and melee range checks.
const lastMonsterMotion=new Map<string,number>();
type MonsterMotion={x:number;y:number;targetId:string|null;mode:"patrol"|"pursuit"|"return"|"defeated";deadUntil:number};
const monsterMotions=new Map<string,Map<string,MonsterMotion>>();
const AGGRO_RADIUS=105, DISENGAGE_RADIUS=135, LEASH_RADIUS=24, CHASE_SPEED=22;
function motionState(lobbyId:string,id:string):MonsterMotion{
 let room=monsterMotions.get(lobbyId);
 if(!room){room=new Map();monsterMotions.set(lobbyId,room);}
 let state=room.get(id);
 if(!state){const [x,y]=worldMonsters[id]!;state={x,y,targetId:null,mode:"patrol",deadUntil:0};room.set(id,state);}
 return state;
}
function monsterPosition(lobbyId:string,id:string):[number,number]{const state=motionState(lobbyId,id);return [state.x,state.y];}
function updateMonsterMotion(lobbyId:string,id:string,now:number,dt:number):MonsterMotion{
 const [hx,hy]=worldMonsters[id]!;const state=motionState(lobbyId,id);
 if(state.deadUntil>now){state.targetId=null;state.mode="defeated";return state;}
 if(state.mode==="defeated"){state.x=hx;state.y=hy;state.mode="patrol";state.deadUntil=0;}
 const prefix=lobbyId+":";
 const candidates=Array.from(playerPositions.entries()).filter(([key,p])=>key.startsWith(prefix)&&now-(playerLastMessageAt.get(key)??0)<1500&&Math.hypot(p.x-hx,p.y-hy)<=DISENGAGE_RADIUS).map(([key,p])=>({id:key.slice(prefix.length),...p,distance:Math.hypot(p.x-state.x,p.y-state.y)})).sort((a,b)=>a.distance-b.distance||a.id.localeCompare(b.id));
 let target=candidates.find(p=>p.id===state.targetId);
 if(!target)target=candidates.find(p=>Math.hypot(p.x-hx,p.y-hy)<=AGGRO_RADIUS);
 state.targetId=target?.id??null;
 let x=hx,y=hy;
 if(target){
  state.mode="pursuit";
  const dx=target.x-hx,dy=target.y-hy,length=Math.hypot(dx,dy);
  const distance=Math.min(LEASH_RADIUS,length);
  if(length>0){x+=dx/length*distance;y+=dy/length*distance;}
 }else if(state.mode==="pursuit"||state.mode==="return"){
  state.mode="return";
  if(Math.hypot(state.x-hx,state.y-hy)<0.5)state.mode="patrol";
 }
 if(state.mode==="patrol"){
  const phase=now/1800+Object.keys(worldMonsters).indexOf(id)*0.7;
  x+=Math.sin(phase)*8;y+=Math.cos(phase)*4;
 }
 const dx=x-state.x,dy=y-state.y,distance=Math.hypot(dx,dy);
 if(distance>0){const fraction=Math.min(1,CHASE_SPEED*dt/distance);state.x+=dx*fraction;state.y+=dy*fraction;}
 return state;
}
function publishMonsterMotion(lobbyId:string,regionId:string,now:number){
 const previous=lastMonsterMotion.get(lobbyId)??now-200;
 if(now-previous<200)return;
 lastMonsterMotion.set(lobbyId,now);
 const dt=Math.min(0.25,(now-previous)/1000);
 broadcast(lobbyId,{type:"monster_motion",regionId,serverTime:now,monsters:Object.keys(monstersForRegion(regionId)).map(monsterId=>{const state=updateMonsterMotion(lobbyId,monsterId,now,dt);return {monsterId,x:state.x,y:state.y,mode:state.mode,targetId:state.targetId};})});
}
const monsterAttackSchema=z.object({type:z.literal("monster_attack"),monsterId:z.string().max(64),guard:z.boolean().optional()});
async function monsterSnapshot(lobbyId:string,regionId:string,sequence:number){
 if(regionId==="six_zone_forsaken_ruins"||regionId==="six_zone_ruined_tower"){
  const monsterId=regionId==="six_zone_forsaken_ruins"?"cassien_encounter":"revienna_encounter";
  const boss=await pool.query<{payload:Record<string,unknown>}>("SELECT payload FROM co_op_world_events WHERE lobby_id=$1 AND event_type='interaction' AND payload->>'kind'='monster_hit' AND payload->>'monsterId'=$3 AND sequence<=$2 ORDER BY sequence DESC LIMIT 1",[lobbyId,sequence,monsterId]);
  const result=[];
  for(const r of boss.rows){
   const w=r.payload.warning as {resolveAt?:number;targetId?:string}|null;
   let warning=r.payload.warning;
   if(w?.resolveAt&&w.targetId){
    const guard=await pool.query("SELECT 1 FROM co_op_world_events WHERE lobby_id=$1 AND actor_player_id=$2 AND event_type='interaction' AND payload->>'kind'='boss_guard' AND payload->>'resolveAt'=$3 AND sequence<=$4 LIMIT 1",[lobbyId,w.targetId,String(w.resolveAt),sequence]);
    warning={...w,guardAcknowledged:Boolean(guard.rowCount)};
    scheduleBossSpecial(lobbyId,w.resolveAt);
   }
   result.push({...r.payload,warning,rewards:[]});
  }
  return result;
 }
 const regionMonsters=monstersForRegion(regionId);
 if(!Object.keys(regionMonsters).length)return [];
 const q=await pool.query<{payload:Record<string,unknown>}>("SELECT DISTINCT ON (payload->>'monsterId') payload FROM co_op_world_events WHERE lobby_id=$1 AND event_type='interaction' AND payload->>'kind'='monster_hit' AND sequence<=$2 AND sequence>COALESCE((SELECT max(sequence) FROM co_op_world_events WHERE lobby_id=$1 AND event_type='region_transition' AND sequence<=$2),0) ORDER BY payload->>'monsterId',sequence DESC",[lobbyId,sequence]);
 const now=Date.now();
 return q.rows.filter(({payload})=>typeof payload.monsterId==="string"&&Object.hasOwn(regionMonsters,payload.monsterId)).map(({payload})=>{
  if(Number(payload.hp)===0&&Number(payload.deadUntil)>now&&typeof payload.monsterId==="string"&&Object.hasOwn(regionMonsters,payload.monsterId)){const state=motionState(lobbyId,payload.monsterId);state.deadUntil=Number(payload.deadUntil);state.mode="defeated";state.targetId=null;}
  if(Number(payload.hp)===0 && Number(payload.deadUntil)<=now)
   return {...payload,hp:monsterMaxHp(String(payload.monsterId)),deadUntil:0,rewards:[]};
  return {...payload,rewards:[]};
 });
}
const bossTimers=new Map<string,ReturnType<typeof setTimeout>>();
function scheduleBossSpecial(lobbyId:string,resolveAt:number){
 const key=`${lobbyId}:${resolveAt}`;
 if(bossTimers.has(key))return;
 const timer=setTimeout(()=>{bossTimers.delete(key);void resolveBossSpecial(lobbyId,resolveAt).catch(error=>console.error("Boss special resolution failed",error));},Math.max(0,resolveAt-Date.now()));
 timer.unref();bossTimers.set(key,timer);
}
async function resolveBossSpecial(lobbyId:string,resolveAt:number){
 const client=await pool.connect();
 try{
  await client.query("BEGIN");
  const room=await client.query("SELECT region_id FROM co_op_lobbies WHERE id=$1 AND status IN ('open','in_world') FOR UPDATE",[lobbyId]);
  const region=room.rows[0]?.region_id;
  if(region!=="six_zone_ruined_tower"&&region!=="six_zone_forsaken_ruins"){await client.query("ROLLBACK");return;}
  const monsterId=region==="six_zone_forsaken_ruins"?"cassien_encounter":"revienna_encounter";
  const latest=await client.query("SELECT payload,actor_player_id FROM co_op_world_events WHERE lobby_id=$1 AND event_type='interaction' AND payload->>'kind'='monster_hit' AND payload->>'monsterId'=$2 ORDER BY sequence DESC LIMIT 1",[lobbyId,monsterId]);
  const old=latest.rows[0]?.payload,w=old?.warning;
  if(!w||w.resolveAt!==resolveAt||old.hp<=0){await client.query("ROLLBACK");return;}
  const target=w.targetId;
  const member=await client.query("SELECT 1 FROM co_op_lobby_members WHERE lobby_id=$1 AND player_id=$2",[lobbyId,target]);
  const guarded=await client.query("SELECT 1 FROM co_op_world_events WHERE lobby_id=$1 AND actor_player_id=$2 AND event_type='interaction' AND payload->>'kind'='boss_guard' AND payload->>'resolveAt'=$3 LIMIT 1",[lobbyId,target,String(resolveAt)]);
  const previous=await client.query("SELECT payload->'counterattack'->>'hp' AS hp FROM co_op_world_events WHERE lobby_id=$1 AND event_type='interaction' AND payload->'counterattack'->>'playerId'=$2 AND sequence>COALESCE((SELECT max(sequence) FROM co_op_world_events WHERE lobby_id=$1 AND event_type='region_transition'),0) ORDER BY sequence DESC LIMIT 1",[lobbyId,target]);
  const before=Number(previous.rows[0]?.hp??100),didGuard=Boolean(guarded.rowCount),damage=Math.min(before,didGuard?Math.ceil(w.damage*0.25):w.damage),knockedOut=before-damage<=0;
  const counterattack=member.rowCount?{playerId:target,hp:knockedOut?100:before-damage,damage,knockedOut}:null;
  const payload={kind:"monster_hit",monsterId,hp:old.hp,maxHp:old.maxHp??(monsterId==="cassien_encounter"?600:1800),phase:old.phase,deadUntil:0,rewards:[],counterattack,warning:null,guarded:didGuard,resolvedSpecial:w.name};
  const sequence=Number((await client.query("UPDATE co_op_lobbies SET next_event_sequence=next_event_sequence+1 WHERE id=$1 RETURNING next_event_sequence-1 AS sequence",[lobbyId])).rows[0].sequence);
  await client.query("INSERT INTO co_op_world_events(lobby_id,sequence,event_type,actor_player_id,payload) VALUES($1,$2,'interaction',$3,$4::jsonb)",[lobbyId,sequence,latest.rows[0].actor_player_id,JSON.stringify(payload)]);
  await client.query("COMMIT");broadcast(lobbyId,{type:"interaction",playerId:latest.rows[0].actor_player_id,sequence,...payload});
 }catch(error){await client.query("ROLLBACK");throw error;}finally{client.release();}
}
const explorationObjectives:Record<string,{id:string;x:number;y:number;radius:number}[]>={
 six_zone_willow_fields:[{id:"willow_bridge",x:900,y:1700,radius:110},{id:"willow_ruins",x:1710,y:1300,radius:110}],
 six_zone_elderwood_grove:[{id:"elderwood_memorial",x:-700,y:1370,radius:135},{id:"elderwood_pillar",x:760,y:1960,radius:135}],
 six_zone_forsaken_ruins:[{id:"ruins_western_brazier",x:-950,y:1300,radius:140},{id:"ruins_central_brazier",x:0,y:1600,radius:140},{id:"ruins_eastern_brazier",x:930,y:2080,radius:140},{id:"cassien_resurrection",x:-1250,y:1050,radius:160}]
};
async function explorationProgress(lobbyId:string,regionId:string,sequence:number){
 if(!explorationObjectives[regionId])return [];
 const q=await pool.query<{id:string}>("SELECT payload->>'objectiveId' AS id FROM co_op_world_events WHERE lobby_id=$1 AND event_type='interaction' AND payload->>'kind'='exploration_objective' AND payload->>'regionId'=$3 AND sequence<=$2 ORDER BY sequence",[lobbyId,sequence,regionId]);
 const completed=new Set(q.rows.map(r=>r.id));
 return explorationObjectives[regionId]!.filter(o=>completed.has(o.id)).map(o=>o.id);
}
async function patrolProgress(lobbyId:string,regionId:string,sequence:number){
 if(regionId!=="six_zone_royal_gate")return [];
 const q=await pool.query<{id:string}>("SELECT DISTINCT payload->>'monsterId' AS id FROM co_op_world_events WHERE lobby_id=$1 AND event_type='interaction' AND payload->>'kind'='monster_hit' AND payload->>'hp'='0' AND sequence<=$2 AND sequence>COALESCE((SELECT max(sequence) FROM co_op_world_events WHERE lobby_id=$1 AND event_type='region_transition' AND sequence<=$2),0)",[lobbyId,sequence]);
 return q.rows.map(r=>r.id).filter(id=>Object.hasOwn(gateMonsters,id)).sort();
}
async function combatHealthSnapshot(lobbyId:string,regionId:string,sequence:number){
 if(!["six_zone_royal_gardens","six_zone_royal_gate","six_zone_willow_fields","six_zone_forsaken_ruins","six_zone_ruined_tower"].includes(regionId))return {};
 const result=await pool.query<{target:string;hp:string}>("SELECT DISTINCT ON (payload->'counterattack'->>'playerId') payload->'counterattack'->>'playerId' AS target,payload->'counterattack'->>'hp' AS hp FROM co_op_world_events WHERE lobby_id=$1 AND event_type='interaction' AND payload->'counterattack' IS NOT NULL AND payload->'counterattack' <> 'null'::jsonb AND sequence<=$2 AND sequence>COALESCE((SELECT max(sequence) FROM co_op_world_events WHERE lobby_id=$1 AND event_type='region_transition' AND sequence<=$2),0) ORDER BY payload->'counterattack'->>'playerId',sequence DESC",[lobbyId,sequence]);
 return Object.fromEntries(result.rows.map(r=>[r.target,Number(r.hp)]));
}
function send(socket:Socket,payload:Record<string,unknown>):void{
 if(socket.readyState===1)socket.send(JSON.stringify(payload));
}
export function broadcast(lobbyId:string,payload:Record<string,unknown>):void{
 for(const socket of rooms.get(lobbyId)??[])send(socket,payload);
}
async function appendEvent(lobbyId:string,playerId:string,eventType:string,payload:Record<string,unknown>):Promise<number>{
 const q=await pool.query<{sequence:string}>(
  "WITH next_event AS (UPDATE co_op_lobbies SET next_event_sequence=next_event_sequence+1,updated_at=now() WHERE id=$1 AND status IN ('open','in_world') AND EXISTS(SELECT 1 FROM co_op_lobby_members WHERE lobby_id=$1 AND player_id=$2) RETURNING next_event_sequence-1 AS sequence) INSERT INTO co_op_world_events(lobby_id,sequence,event_type,actor_player_id,payload) SELECT $1,next_event.sequence,$3,$2,$4::jsonb FROM next_event RETURNING sequence::text",
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
  socketPlayers.set(socket,playerId);
  peers.add(socket);rooms.set(lobbyId,peers);
  send(socket,{type:"connected",lobbyId,playerId});
  void pool.query("UPDATE player_presence SET state='in_world',last_heartbeat_at=now(),updated_at=now() WHERE player_id=$1",[playerId]).catch(()=>{});
  void pool.query(
   "SELECT p.id,p.name,p.level,"+verifiedTitleSql+" AS title_id,m.role,l.region_id,l.next_event_sequence-1 AS last_sequence,latest.payload->>'x' AS x,latest.payload->>'y' AS y FROM co_op_lobby_members m JOIN players p ON p.id=m.player_id JOIN co_op_lobbies l ON l.id=m.lobby_id LEFT JOIN LATERAL (SELECT payload FROM co_op_world_events WHERE lobby_id=m.lobby_id AND actor_player_id=m.player_id AND event_type='position' AND sequence>COALESCE((SELECT max(sequence) FROM co_op_world_events WHERE lobby_id=m.lobby_id AND event_type='region_transition'),0) ORDER BY sequence DESC LIMIT 1) latest ON true WHERE m.lobby_id=$1 ORDER BY m.joined_at",
   [lobbyId])
   .then(async result=>{
    const now=Date.now();
    const regionId=String(result.rows[0]?.region_id??"");
    const spawn=REGION_SPAWNS[regionId];
    for(const member of result.rows){
     const x=member.x!==null?Number(member.x):spawn?.x;
     const y=member.y!==null?Number(member.y):spawn?.y;
     if(Number.isFinite(x)&&Number.isFinite(y)){
      member.x=x;member.y=y;
      const key=lobbyId+":"+member.id;
      if(!playerPositions.has(key))playerPositions.set(key,{x:Number(x),y:Number(y),at:now});
     }
    }
    const sequence=Number(result.rows[0]?.last_sequence??0);
    send(socket,{type:"snapshot",members:result.rows.map(m=>({...m,title:titleName(m.title_id)})),sequence,monsters:await monsterSnapshot(lobbyId,regionId,sequence),combatHealth:await combatHealthSnapshot(lobbyId,regionId,sequence),patrolCleared:await patrolProgress(lobbyId,regionId,sequence),explorationCleared:await explorationProgress(lobbyId,regionId,sequence)});
   })
   .catch(error=>{
    request.log.error({err:error,lobbyId,playerId},"initial realtime snapshot unavailable");
    send(socket,{type:"error",code:"snapshot_unavailable"});
    socket.close(1011,"snapshot_unavailable");
   });

  let lobbyRegionId="";
  let regionEpoch=0;
  let queuedMessages=0;
  const lobbyRegionReady=pool.query<{region_id:string;epoch:string}>("SELECT region_id,COALESCE((SELECT max(sequence) FROM co_op_world_events WHERE lobby_id=$1 AND event_type='region_transition'),0)::text AS epoch FROM co_op_lobbies WHERE id=$1 AND status IN ('open','in_world')",[lobbyId]).then(result=>{
   lobbyRegionId=result.rows[0]?.region_id??"";
   regionEpoch=Number(result.rows[0]?.epoch??0);
   return lobbyRegionId.length>0;
  }).catch(error=>{
   request.log.warn({err:error,lobbyId},"lobby region lookup failed");
   return false;
  });

  let sessionChecking=false;
  const sessionTimer=setInterval(()=>{
   if(socket.readyState!==1||sessionChecking)return;
   sessionChecking=true;
   void pool.query("SELECT 1 FROM accounts WHERE id=$1 AND status='active' AND token_version=$2",[accountId,tokenVersion]).then(result=>{
    if(!result.rowCount&&socket.readyState===1){send(socket,{type:"rejected",reason:"session_revoked"});socket.close(1008,"session_revoked");}
   }).catch(()=>{if(socket.readyState===1)socket.close(1011,"session_validation_unavailable");}).finally(()=>{sessionChecking=false;});
  },15000);
  sessionTimer.unref();
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
     const titles=await pool.query("SELECT p.id AS \"playerId\","+verifiedTitleSql+" AS title_id FROM co_op_lobby_members m JOIN players p ON p.id=m.player_id WHERE m.lobby_id=$1",[lobbyId]);
       send(socket,{type:"player_titles",players:titles.rows.map(r=>({playerId:r.playerId,title:titleName(r.title_id)}))});
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
     const crossedRegion=events.rows.some(event=>event.event_type==="region_transition");
     if(events.rows.length>0&&events.rows.length<=200&&!crossedRegion)send(socket,{type:"replay",events:events.rows});
     else if(events.rows.length>200||crossedRegion){
      const snapshot=await pool.query(
       "SELECT p.id,p.name,p.level,"+verifiedTitleSql+" AS title_id,m.role,l.region_id,l.next_event_sequence-1 AS last_sequence,latest.payload->>'x' AS x,latest.payload->>'y' AS y FROM co_op_lobby_members m JOIN players p ON p.id=m.player_id JOIN co_op_lobbies l ON l.id=m.lobby_id LEFT JOIN LATERAL (SELECT payload FROM co_op_world_events WHERE lobby_id=m.lobby_id AND actor_player_id=m.player_id AND event_type='position' AND sequence>COALESCE((SELECT max(sequence) FROM co_op_world_events WHERE lobby_id=m.lobby_id AND event_type='region_transition'),0) ORDER BY sequence DESC LIMIT 1) latest ON true WHERE m.lobby_id=$1 ORDER BY m.joined_at",
       [lobbyId]);
      const regionId=String(snapshot.rows[0]?.region_id??lobbyRegionId);
      const spawn=REGION_SPAWNS[regionId];
      const snapshotAt=Date.now();
      for(const member of snapshot.rows){
       const x=member.x!==null?Number(member.x):spawn?.x;
       const y=member.y!==null?Number(member.y):spawn?.y;
       if(Number.isFinite(x)&&Number.isFinite(y)){member.x=x;member.y=y;const key=lobbyId+":"+member.id;if(!playerPositions.has(key))playerPositions.set(key,{x:Number(x),y:Number(y),at:snapshotAt});}
      }
      const sequence=Number(snapshot.rows[0]?.last_sequence??0);
      send(socket,{type:"snapshot",members:snapshot.rows.map(m=>({...m,title:titleName(m.title_id)})),sequence,monsters:await monsterSnapshot(lobbyId,regionId,sequence),combatHealth:await combatHealthSnapshot(lobbyId,regionId,sequence),patrolCleared:await patrolProgress(lobbyId,regionId,sequence),explorationCleared:await explorationProgress(lobbyId,regionId,sequence),requires_resync:true});
     }else send(socket,{type:"replay",events:[]});
     return;
    }
    const attack=monsterAttackSchema.safeParse(message);
    if(attack.success){
     const monsterId=attack.data.monsterId;
     const ravienna=monsterId==="revienna_encounter"&&lobbyRegionId==="six_zone_ruined_tower";
     const cassien=monsterId==="cassien_encounter"&&lobbyRegionId==="six_zone_forsaken_ruins";
     const boss=ravienna||cassien;
     const guard=attack.data.guard===true;
     if(guard&&!boss){send(socket,{type:"rejected",reason:"guard_unavailable"});return;}
     const regionMonsters=monstersForRegion(lobbyRegionId);
     const spawn: [number,number]|undefined=ravienna?[0,1050]:cassien?[-908,1196]:Object.hasOwn(regionMonsters,monsterId)?regionMonsters[monsterId]:undefined;
     if(!spawn){send(socket,{type:"rejected",reason:"unknown_monster"});return;}
     const client=await pool.connect();
     try{
      await client.query("BEGIN");
      const current=await client.query<{region_id:string}>("SELECT region_id FROM co_op_lobbies WHERE id=$1 AND status IN ('open','in_world') FOR UPDATE",[lobbyId]);
      if(socket.readyState!==1||!(await client.query("SELECT 1 FROM co_op_lobby_members WHERE lobby_id=$1 AND player_id=$2",[lobbyId,playerId])).rowCount){await client.query("ROLLBACK");return;}
      const epoch=await client.query<{seq:string}>("SELECT COALESCE(max(sequence),0)::text AS seq FROM co_op_world_events WHERE lobby_id=$1 AND event_type='region_transition'",[lobbyId]);
      if(current.rows[0]?.region_id!==lobbyRegionId||Number(epoch.rows[0]?.seq)!==regionEpoch){await client.query("ROLLBACK");send(socket,{type:"rejected",reason:"stale_region"});return;}
      const actor=await client.query<{payload:{x:number;y:number}}>("SELECT payload FROM co_op_world_events WHERE lobby_id=$1 AND actor_player_id=$2 AND event_type='position' AND sequence>$3 ORDER BY sequence DESC LIMIT 1",[lobbyId,playerId,regionEpoch]);
      const at=actor.rows[0]?.payload??REGION_SPAWNS[lobbyRegionId];
      const movingPosition=boss?spawn:monsterPosition(lobbyId,monsterId);
      if(!at||Math.hypot(at.x-movingPosition[0],at.y-movingPosition[1])>(boss?150:85)){await client.query("ROLLBACK");send(socket,{type:"rejected",reason:"attack_out_of_range"});return;}
      const time=Date.now();
      const last=await client.query<{at:string}>("SELECT (extract(epoch from created_at)*1000)::text AS at FROM co_op_world_events WHERE lobby_id=$1 AND actor_player_id=$2 AND event_type='interaction' AND payload->>'kind'='monster_hit' AND sequence>$3 ORDER BY sequence DESC LIMIT 1",[lobbyId,playerId,regionEpoch]);
      if(!guard&&last.rows[0]&&time-Number(last.rows[0].at)<500){await client.query("ROLLBACK");send(socket,{type:"rejected",reason:"attack_cooldown"});return;}
      const previous=await client.query<{payload:{hp:number;deadUntil:number;warning?:{name:string;resolveAt:number;damage:number;targetId:string}|null}}>("SELECT payload FROM co_op_world_events WHERE lobby_id=$1 AND event_type='interaction' AND payload->>'kind'='monster_hit' AND payload->>'monsterId'=$2 AND sequence>$3 ORDER BY sequence DESC LIMIT 1",[lobbyId,monsterId,boss?0:regionEpoch]);
      const old=previous.rows[0]?.payload;
      if(old&&(old.deadUntil>time||(boss&&old.hp===0))){await client.query("ROLLBACK");send(socket,{type:"rejected",reason:"monster_defeated"});return;}
            const pending=boss?old?.warning:null;
      if(guard){
       if(!pending||pending.targetId!==playerId||time>=pending.resolveAt){await client.query("ROLLBACK");send(socket,{type:"rejected",reason:"guard_unavailable"});return;}
       const already=await client.query("SELECT 1 FROM co_op_world_events WHERE lobby_id=$1 AND actor_player_id=$2 AND payload->>'kind'='boss_guard' AND payload->>'resolveAt'=$3",[lobbyId,playerId,String(pending.resolveAt)]);
       if(already.rowCount){await client.query("ROLLBACK");return;}
       const seq=Number((await client.query("UPDATE co_op_lobbies SET next_event_sequence=next_event_sequence+1 WHERE id=$1 RETURNING next_event_sequence-1 AS sequence",[lobbyId])).rows[0].sequence);
       const payload={kind:"boss_guard",monsterId,resolveAt:pending.resolveAt};
       await client.query("INSERT INTO co_op_world_events(lobby_id,sequence,event_type,actor_player_id,payload) VALUES($1,$2,'interaction',$3,$4::jsonb)",[lobbyId,seq,playerId,JSON.stringify(payload)]);
       await client.query("COMMIT");broadcast(lobbyId,{type:"interaction",playerId,sequence:seq,...payload});return;
      }
      if(pending){await client.query("ROLLBACK");send(socket,{type:"rejected",reason:"special_windup"});scheduleBossSpecial(lobbyId,pending.resolveAt);return;}
      const gate=Object.hasOwn(gateMonsters,monsterId);
      const maxHp=ravienna?1800:cassien?600:monsterMaxHp(monsterId);
      const hp=Math.max(0,(old&&old.hp>0?old.hp:maxHp)-(guard?0:boss?100:25));
      const phase=ravienna?(hp<=594?3:hp<=1188?2:1):1;
      const warning=cassien?cassienSpecial(hp,playerId,time):ravienna&&!guard&&!pending&&hp>0&&hp%400===0?{name:hp===1600?"Corruption Bolt":hp===1200?"Shadow Lash":hp===800?"Hollow Wail":"Eclipse Verdict",targetId:playerId,resolveAt:time+1800,damage:phase===1?24:phase===2?32:40}:null;
      const seq=await client.query<{sequence:string}>("UPDATE co_op_lobbies SET next_event_sequence=next_event_sequence+1,updated_at=now() WHERE id=$1 RETURNING (next_event_sequence-1)::text AS sequence",[lobbyId]);
      const sequence=Number(seq.rows[0]!.sequence);
      const rewards:Array<{playerId:string;gold:number;xp:number;items:Record<string,number>;crystals?:number;ancientCoins?:number}>=[];
      if(hp===0){
       const gold=ravienna?2000:cassien?180:gate?25:monsterId.startsWith("crownling_")?22:15;
       const xp=ravienna?3000:cassien?140:gate?18:monsterId.startsWith("crownling_")?17:10;
       const contributors=await client.query<{player_id:string}>("SELECT DISTINCT e.actor_player_id AS player_id FROM co_op_world_events e JOIN co_op_lobby_members m ON m.lobby_id=e.lobby_id AND m.player_id=e.actor_player_id WHERE e.lobby_id=$1 AND e.event_type='interaction' AND e.payload->>'kind'='monster_hit' AND e.payload->>'monsterId'=$2 AND e.sequence>GREATEST($3,COALESCE((SELECT max(sequence) FROM co_op_world_events WHERE lobby_id=$1 AND event_type='interaction' AND payload->>'kind'='monster_hit' AND payload->>'monsterId'=$2 AND payload->>'hp'='0'),0))",[lobbyId,monsterId,boss?0:regionEpoch]);
       const ids=[...new Set([playerId,...contributors.rows.map(r=>r.player_id)])].sort();
       for(const recipient of ids){
        await client.query("SELECT id FROM players WHERE id=$1 FOR UPDATE",[recipient]);
        const key=`coop:${lobbyId}:${sequence}:${monsterId}`;
        const already=await client.query("SELECT 1 FROM currency_ledger WHERE player_id=$1 AND idempotency_key=$2",[recipient,key]);
        if(already.rowCount)continue;
        await recordOnlineDailyVictory(client,recipient,ids.length>1,lobbyRegionId,monsterId);
        const wallet=await client.query<{balance:string}>("INSERT INTO player_currencies(player_id,currency_id,balance) VALUES($1,'gold',$2) ON CONFLICT(player_id,currency_id) DO UPDATE SET balance=player_currencies.balance+EXCLUDED.balance RETURNING balance::text",[recipient,gold]);
        await client.query("INSERT INTO currency_ledger(player_id,currency_id,delta,balance_after,reason,ref_type,ref_id,idempotency_key) VALUES($1,'gold',$2,$3,'coop_monster_defeat','coop_event',$4,$5)",[recipient,gold,wallet.rows[0]!.balance,`${lobbyId}:${sequence}`,key]);
        await client.query("UPDATE players SET xp=xp+$2,updated_at=now() WHERE id=$1",[recipient,xp]);
        await grantPartyXp(client,recipient,xp);
        if(boss)for(const [currency,amount] of (cassien?[["crystals",20]]:[["crystals",400],["ancient_coins",5]]) as [string,number][]){
         const balance=await client.query<{balance:string}>("INSERT INTO player_currencies(player_id,currency_id,balance) VALUES($1,$2,$3) ON CONFLICT(player_id,currency_id) DO UPDATE SET balance=player_currencies.balance+EXCLUDED.balance RETURNING balance::text",[recipient,currency,amount]);
         await client.query("INSERT INTO currency_ledger(player_id,currency_id,delta,balance_after,reason,ref_type,ref_id,idempotency_key) VALUES($1,$2,$3,$4,'coop_monster_defeat','coop_event',$5,$6)",[recipient,currency,amount,balance.rows[0]!.balance,`${lobbyId}:${sequence}`,key+":"+currency]);
        }
        if(cassien){rewards.push({playerId:recipient,gold,xp,items:{},crystals:20});continue;}
        const itemId=boss?"gothic_shard":gate||monsterId.startsWith("crownling_")?"moonpetal":"glade_sap";
        const quantity=boss?4:1;
        const itemName=boss?"Gothic Shard":itemId==="moonpetal"?"Moonpetal":"Glade Sap";
        await client.query("INSERT INTO items(id,display_name,category,rarity) VALUES($1,$2,'material',$3) ON CONFLICT(id) DO NOTHING",[itemId,itemName,boss?"rare":itemId==="moonpetal"?"rare":"common"]);
        const stock=await client.query<{quantity:string}>("INSERT INTO inventory_items(player_id,item_id,quantity) VALUES($1,$2,$3) ON CONFLICT(player_id,item_id) DO UPDATE SET quantity=inventory_items.quantity+EXCLUDED.quantity RETURNING quantity::text",[recipient,itemId,quantity]);
        await client.query("INSERT INTO item_ledger(player_id,item_id,delta,quantity_after,reason,ref_type,ref_id,idempotency_key) VALUES($1,$2,$6,$3,'coop_monster_defeat','coop_event',$4,$5)",[recipient,itemId,stock.rows[0]!.quantity,`${lobbyId}:${sequence}`,key+":"+itemId,quantity]);
        rewards.push({playerId:recipient,gold,xp,items:{[itemId]:quantity},...(boss?{crystals:400,ancientCoins:5}:{})});
       }
      }
            // Reactive melee retaliation; HP and timing are decided only on the server.
      let counterattack:{playerId:string;hp:number;damage:number;knockedOut:boolean}|null=null;
      if(hp>0&&!warning&&Math.hypot(at.x-movingPosition[0],at.y-movingPosition[1])<=(boss?150:45)){
       const lastCounter=await client.query<{at:string}>("SELECT (extract(epoch from created_at)*1000)::text AS at FROM co_op_world_events WHERE lobby_id=$1 AND event_type='interaction' AND payload->>'monsterId'=$2 AND payload->'counterattack' IS NOT NULL AND payload->'counterattack' <> 'null'::jsonb AND sequence>$3 ORDER BY sequence DESC LIMIT 1",[lobbyId,monsterId,regionEpoch]);
       if(pending||!lastCounter.rows[0]||time-Number(lastCounter.rows[0].at)>=1200){
        const previousHealth=await client.query<{hp:string}>("SELECT payload->'counterattack'->>'hp' AS hp FROM co_op_world_events WHERE lobby_id=$1 AND event_type='interaction' AND payload->'counterattack'->>'playerId'=$2 AND sequence>$3 ORDER BY sequence DESC LIMIT 1",[lobbyId,playerId,regionEpoch]);
        const before=Number(previousHealth.rows[0]?.hp??100);
        const damage=Math.min(before,ravienna?12+phase*4:cassien?18:gate?15:12);
        const knockedOut=before-damage<=0;
        counterattack={playerId,hp:knockedOut?100:before-damage,damage,knockedOut};
       }
      }
      const payload={kind:"monster_hit",monsterId,hp,maxHp,phase,deadUntil:hp===0&&!boss?time+15000:0,rewards,counterattack,warning,guarded:false,resolvedSpecial:null};
      await client.query("INSERT INTO co_op_world_events(lobby_id,sequence,event_type,actor_player_id,payload) VALUES($1,$2,'interaction',$3,$4::jsonb)",[lobbyId,sequence,playerId,JSON.stringify(payload)]);
      await client.query("COMMIT");
      if(hp===0&&!boss){const state=motionState(lobbyId,monsterId);state.deadUntil=payload.deadUntil;state.targetId=null;state.mode="defeated";}
      broadcast(lobbyId,{type:"interaction",playerId,sequence,...payload});
      if(warning)scheduleBossSpecial(lobbyId,warning.resolveAt);
     }catch(e){await client.query("ROLLBACK");throw e;}finally{client.release();}
     return;
    }
    if(candidate.type==="exploration_objective"){
     const objectives=explorationObjectives[lobbyRegionId];
     const objectiveId=typeof candidate.objectiveId==="string"?candidate.objectiveId:"";
     if(!objectives?.some(o=>o.id===objectiveId)){send(socket,{type:"rejected",reason:"unknown_objective"});return;}
     const client=await pool.connect();
     try{
      await client.query("BEGIN");
      const state=await client.query<{region_id:string;sequence:string}>("SELECT region_id,(next_event_sequence-1)::text AS sequence FROM co_op_lobbies WHERE id=$1 AND status IN ('open','in_world') FOR UPDATE",[lobbyId]);
      const row=state.rows[0];
      const epoch=await client.query<{sequence:string}>("SELECT COALESCE(max(sequence),0)::text AS sequence FROM co_op_world_events WHERE lobby_id=$1 AND event_type='region_transition'",[lobbyId]);
      if(!row||row.region_id!==lobbyRegionId||Number(epoch.rows[0]?.sequence)!==regionEpoch||socket.readyState!==1||!(await client.query("SELECT 1 FROM co_op_lobby_members WHERE lobby_id=$1 AND player_id=$2",[lobbyId,playerId])).rowCount){await client.query("ROLLBACK");return;}
      if(lobbyRegionId==="six_zone_forsaken_ruins"&&!(await client.query("SELECT 1 FROM co_op_world_events WHERE lobby_id=$1 AND event_type='interaction' AND payload->>'monsterId'='cassien_encounter' AND payload->>'hp'='0' LIMIT 1",[lobbyId])).rowCount){await client.query("ROLLBACK");send(socket,{type:"rejected",reason:"cassien_defeat_required"});return;}
      const done=await client.query<{id:string}>("SELECT payload->>'objectiveId' AS id FROM co_op_world_events WHERE lobby_id=$1 AND event_type='interaction' AND payload->>'kind'='exploration_objective' AND payload->>'regionId'=$2",[lobbyId,lobbyRegionId]);
      const completed=new Set(done.rows.map(r=>r.id));
      if(completed.has(objectiveId)){await client.query("ROLLBACK");send(socket,{type:"rejected",reason:"objective_already_complete"});return;}
      const next=objectives.find(o=>!completed.has(o.id));
      if(!next||next.id!==objectiveId){await client.query("ROLLBACK");send(socket,{type:"rejected",reason:"objective_order_required"});return;}
      const position=await client.query<{payload:{x:number;y:number}}>("SELECT payload FROM co_op_world_events WHERE lobby_id=$1 AND actor_player_id=$2 AND event_type='position' AND sequence>$3 ORDER BY sequence DESC LIMIT 1",[lobbyId,playerId,regionEpoch]);
      const at=position.rows[0]?.payload??REGION_SPAWNS[lobbyRegionId];
      if(!at||Math.hypot(at.x-next.x,at.y-next.y)>next.radius){await client.query("ROLLBACK");send(socket,{type:"rejected",reason:"objective_proximity_required"});return;}
      const seq=await client.query<{sequence:string}>("UPDATE co_op_lobbies SET next_event_sequence=next_event_sequence+1,updated_at=now() WHERE id=$1 RETURNING (next_event_sequence-1)::text AS sequence",[lobbyId]);
      const sequence=Number(seq.rows[0]!.sequence);
      completed.add(objectiveId);
      const payload={kind:"exploration_objective",regionId:lobbyRegionId,objectiveId,completed:objectives.filter(o=>completed.has(o.id)).map(o=>o.id)};
        await client.query("INSERT INTO online_achievement_exploration(player_id,region_id,objective_id) VALUES($1,$2,$3) ON CONFLICT DO NOTHING",[playerId,lobbyRegionId,objectiveId]);
        await client.query("INSERT INTO online_season_exploration(player_id,season_start,region_id,objective_id) VALUES($1,date_trunc('month',CURRENT_TIMESTAMP AT TIME ZONE 'UTC')::date,$2,$3) ON CONFLICT DO NOTHING",[playerId,lobbyRegionId,objectiveId]);

      await client.query("INSERT INTO co_op_world_events(lobby_id,sequence,event_type,actor_player_id,payload) VALUES($1,$2,'interaction',$3,$4::jsonb)",[lobbyId,sequence,playerId,JSON.stringify(payload)]);
      await client.query("COMMIT");
      broadcast(lobbyId,{type:"interaction",playerId,sequence,...payload});
     }catch(e){await client.query("ROLLBACK");throw e;}finally{client.release();}
     return;
    }
    if(candidate.type==="region_transition"){
     const destination=typeof candidate.regionId==="string"?candidate.regionId:"";
     const portal=EXPEDITION_PORTALS[lobbyRegionId]?.[destination];
     if(!portal){send(socket,{type:"rejected",reason:"invalid_region_transition"});return;}
     const client=await pool.connect();
     try{
      await client.query("BEGIN");
      const current=await client.query<{region_id:string;leader_player_id:string}>("SELECT region_id,leader_player_id FROM co_op_lobbies WHERE id=$1 AND status IN ('open','in_world') FOR UPDATE",[lobbyId]);
      const state=current.rows[0];
      const epoch=await client.query<{sequence:string}>("SELECT COALESCE(max(sequence),0)::text AS sequence FROM co_op_world_events WHERE lobby_id=$1 AND event_type='region_transition'",[lobbyId]);
      if(!state||state.region_id!==lobbyRegionId||Number(epoch.rows[0]?.sequence)!==regionEpoch||state.leader_player_id!==playerId){await client.query("ROLLBACK");send(socket,{type:"rejected",reason:"leader_or_region_required"});return;}
      const position=await client.query<{payload:{x:number;y:number}}>("SELECT payload FROM co_op_world_events WHERE lobby_id=$1 AND actor_player_id=$2 AND event_type='position' AND sequence>$3 ORDER BY sequence DESC LIMIT 1",[lobbyId,playerId,regionEpoch]);
      const at=position.rows[0]?.payload??REGION_SPAWNS[lobbyRegionId];
      if(!at||Math.hypot(at.x-portal[0],at.y-portal[1])>220){await client.query("ROLLBACK");send(socket,{type:"rejected",reason:"portal_proximity_required"});return;}
      const seq=await client.query<{sequence:string}>("UPDATE co_op_lobbies SET region_id=$2,next_event_sequence=next_event_sequence+1,updated_at=now() WHERE id=$1 RETURNING (next_event_sequence-1)::text AS sequence",[lobbyId,destination]);
      const sequence=Number(seq.rows[0]!.sequence);
      await client.query("INSERT INTO co_op_world_events(lobby_id,sequence,event_type,actor_player_id,payload) VALUES($1,$2,'region_transition',$3,$4::jsonb)",[lobbyId,sequence,playerId,JSON.stringify({regionId:destination})]);
      await client.query("UPDATE player_presence SET region_id=$2,updated_at=now() WHERE player_id IN (SELECT player_id FROM co_op_lobby_members WHERE lobby_id=$1)",[lobbyId,destination]);
      await client.query("COMMIT");
      for(const key of playerPositions.keys())if(key.startsWith(lobbyId+":"))playerPositions.delete(key);
      monsterMotions.delete(lobbyId);lastMonsterMotion.delete(lobbyId);
      broadcast(lobbyId,{type:"region_transition",regionId:destination,sequence});
     }catch(e){await client.query("ROLLBACK");throw e;}finally{client.release();}
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
     const writer=await pool.connect();
     let sequence:number;
     try{
      await writer.query("BEGIN");
      const row=await writer.query<{region_id:string}>("SELECT region_id FROM co_op_lobbies WHERE id=$1 AND status IN ('open','in_world') FOR UPDATE",[lobbyId]);
      if(socket.readyState!==1||!(await writer.query("SELECT 1 FROM co_op_lobby_members WHERE lobby_id=$1 AND player_id=$2",[lobbyId,playerId])).rowCount){await writer.query("ROLLBACK");return;}
      const epoch=await writer.query<{sequence:string}>("SELECT COALESCE(max(sequence),0)::text AS sequence FROM co_op_world_events WHERE lobby_id=$1 AND event_type='region_transition'",[lobbyId]);
      if(row.rows[0]?.region_id!==lobbyRegionId||Number(epoch.rows[0]?.sequence)!==regionEpoch){await writer.query("ROLLBACK");send(socket,{type:"rejected",reason:"stale_region"});return;}
      const seq=await writer.query<{sequence:string}>("UPDATE co_op_lobbies SET next_event_sequence=next_event_sequence+1,updated_at=now() WHERE id=$1 RETURNING (next_event_sequence-1)::text AS sequence",[lobbyId]);
      sequence=Number(seq.rows[0]!.sequence);
      await writer.query("INSERT INTO co_op_world_events(lobby_id,sequence,event_type,actor_player_id,payload) VALUES($1,$2,'position',$3,$4::jsonb)",[lobbyId,sequence,playerId,JSON.stringify({x:position.data.x,y:position.data.y})]);
      await writer.query("COMMIT");
     }catch(e){await writer.query("ROLLBACK");throw e;}finally{writer.release();}
     playerPositions.set(movementKey,{x:position.data.x,y:position.data.y,at:now});
     playerLastMessageAt.set(movementKey,now);
     broadcast(lobbyId,{...event,sequence});
     if(Object.keys(monstersForRegion(lobbyRegionId)).length)publishMonsterMotion(lobbyId,lobbyRegionId,Date.now());
     return;
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
   clearInterval(sessionTimer);
   peers.delete(socket);
   if(peers.size===0&&rooms.get(lobbyId)===peers){rooms.delete(lobbyId);lastMonsterMotion.delete(lobbyId);monsterMotions.delete(lobbyId);for(const key of playerPositions.keys())if(key.startsWith(lobbyId+":")){playerPositions.delete(key);playerLastMessageAt.delete(key);}}
   // Pending specials are durable events; allow their short timer to resolve even when everyone disconnects.
   realtimeLimits.close(playerId);
   if(realtimeLimits.connectionCount(playerId)===0){
    const movementKey=lobbyId+":"+playerId;
    playerPositions.delete(movementKey);
    playerLastMessageAt.delete(movementKey);
    void pool.query(
     "UPDATE player_presence SET state=CASE WHEN EXISTS(SELECT 1 FROM co_op_lobby_members WHERE player_id=$1) THEN 'in_lobby' ELSE 'online' END,last_heartbeat_at=now(),updated_at=now() WHERE player_id=$1 AND state='in_world'",
     [playerId]
    ).catch(error=>request.log.warn({err:error,playerId},"presence cleanup failed"));
   }
  });
 });
};
