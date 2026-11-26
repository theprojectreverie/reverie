import Fastify from 'fastify';
import jwt from '@fastify/jwt';
import websocket from '@fastify/websocket';
import WebSocket from 'ws';
import {randomBytes} from 'node:crypto';
import {config} from '../src/config.ts';
import {pool} from '../src/db.ts';
import {authRoutes} from '../src/routes/auth.ts';
import {coopRoutes} from '../src/routes/coop.ts';
import {realtimeRoutes} from '../src/routes/realtime.ts';
import assert from 'node:assert/strict';
assert.ok(['127.0.0.1','localhost','[::1]'].includes(new URL(config.DATABASE_URL).hostname));
const app=Fastify({logger:false}), suffix=randomBytes(5).toString('hex'),names=[`QaA${suffix}`,`QaB${suffix}`],emails=names.map(n=>n.toLowerCase()+'@example.test'),tokens=[],sockets=[];
let lobby='';
const sleep=ms=>new Promise(r=>setTimeout(r,ms));
async function call(path,body,token){const r=await app.inject({method:'POST',url:path,payload:body,headers:token?{authorization:`Bearer ${token}`}:{}});assert.ok(r.statusCode<300,`${path}: ${r.statusCode}`);return r.json();}
function peer(url,token){const ws=new WebSocket(url,{headers:{authorization:`Bearer ${token}`}});sockets.push(ws);const messages=[];ws.on('message',raw=>messages.push(JSON.parse(String(raw))));return {ws,async wait(fn){const end=Date.now()+7000;while(Date.now()<end){const i=messages.findIndex(fn);if(i>=0)return messages.splice(i,1)[0];await sleep(10);}throw new Error('Timed out waiting for message');},send(data){ws.send(JSON.stringify(data));},async close(){if(ws.readyState===WebSocket.CLOSED)return;await new Promise(r=>{ws.once('close',r);ws.close();});}};}
async function place(ids,x,y){for(const id of ids){const seq=(await pool.query("UPDATE co_op_lobbies SET next_event_sequence=next_event_sequence+1 WHERE id=$1 RETURNING next_event_sequence-1 AS seq",[lobby])).rows[0].seq;await pool.query("INSERT INTO co_op_world_events(lobby_id,sequence,event_type,actor_player_id,payload) VALUES($1,$2,'position',$3,$4::jsonb)",[lobby,seq,id,JSON.stringify({x,y})]);}}
try{
 await app.register(jwt,{secret:config.JWT_SECRET});await app.register(websocket);await app.register(authRoutes,{prefix:'/v1/auth'});await app.register(coopRoutes,{prefix:'/v1/co-op'});await app.register(realtimeRoutes,{prefix:'/v1'});await app.listen({host:'127.0.0.1',port:0});
 for(let i=0;i<2;i++){const password=randomBytes(16).toString('hex');await call('/v1/auth/register',{email:emails[i],playerName:names[i],password});tokens.push((await call('/v1/auth/login',{playerName:names[i],password})).accessToken);}
 const created=await call('/v1/co-op/lobbies',{regionId:'six_zone_forsaken_ruins',maxMembers:4},tokens[0]);lobby=created.lobbyId;await call('/v1/co-op/lobbies/join',{inviteCode:created.inviteCode},tokens[1]);
 const ids=(await pool.query("SELECT player_id FROM co_op_lobby_members WHERE lobby_id=$1 ORDER BY joined_at",[lobby])).rows.map(x=>x.player_id);
 const url=`ws://127.0.0.1:${app.server.address().port}/v1/realtime?lobbyId=${lobby}`;let a,b;
 async function connect(){a=peer(url,tokens[0]);b=peer(url,tokens[1]);await a.wait(m=>m.type==='connected');await b.wait(m=>m.type==='connected');return Promise.all([a.wait(m=>m.type==='snapshot'),b.wait(m=>m.type==='snapshot')]);}
 await place(ids,-908,1286);await connect();
 a.send({type:'exploration_objective',objectiveId:'ruins_western_brazier'});await a.wait(m=>m.reason==='cassien_defeat_required');
 a.send({type:'monster_attack',monsterId:'revienna_encounter'});await a.wait(m=>m.reason==='unknown_monster');
 for(let i=0;i<6;i++){
  await sleep(550);const striker=i%2===0?a:b;striker.send({type:'monster_attack',monsterId:'cassien_encounter'});
  const hp=500-i*100;const event=await a.wait(m=>m.kind==='monster_hit'&&m.hp===hp);const other=await b.wait(m=>m.kind==='monster_hit'&&m.hp===hp);assert.deepEqual(event,other);assert.equal(event.maxHp,600);
  if(hp===400||hp===200){
   const special=hp===400?'Crimson Crescent':'Crimson Requiem';assert.equal(event.warning.name,special);assert.equal(event.warning.targetId,ids[1]);
   a.send({type:'monster_attack',monsterId:'cassien_encounter',guard:true});await a.wait(m=>m.reason==='guard_unavailable');
   a.send({type:'monster_attack',monsterId:'cassien_encounter'});await a.wait(m=>m.reason==='special_windup');
   if(hp===400){
    b.send({type:'monster_attack',monsterId:'cassien_encounter',guard:true});const ack=await b.wait(m=>m.kind==='boss_guard');await a.wait(m=>m.kind==='boss_guard');assert.equal(ack.resolveAt,event.warning.resolveAt);
    await Promise.all([a.close(),b.close()]);const snaps=await connect();assert.ok(snaps.every(s=>s.monsters[0].hp===400&&s.monsters[0].warning?.guardAcknowledged===true));console.log('PASS guarded warning restored on reconnect');
   }
   const resolved=await a.wait(m=>m.resolvedSpecial===special);const resolvedOther=await b.wait(m=>m.resolvedSpecial===special);assert.deepEqual(resolved,resolvedOther);assert.equal(resolved.hp,hp);assert.equal(resolved.warning,null);assert.equal(resolved.guarded,hp===400);assert.equal(resolved.counterattack.damage,hp===400?7:40);console.log('PASS '+special+' shared resolution and '+(hp===400?'guarded':'unguarded')+' damage');
  }
  if(!hp){assert.equal(event.rewards.length,2);assert.ok(event.rewards.every(r=>r.gold===180&&r.xp===140&&r.crystals===20));}
 }
 await sleep(550);a.send({type:'monster_attack',monsterId:'cassien_encounter'});await a.wait(m=>m.reason==='monster_defeated');console.log('PASS Cassien shared HP, two individual rewards, no repeat kill');
 const objectives=[['ruins_western_brazier',-950,1300],['ruins_central_brazier',0,1600],['ruins_eastern_brazier',930,2080],['cassien_resurrection',-1250,1050]];
 a.send({type:'exploration_objective',objectiveId:'cassien_resurrection'});await a.wait(m=>m.reason==='objective_order_required');
 for(let i=0;i<objectives.length;i++){await Promise.all([a.close(),b.close()]);const [id,x,y]=objectives[i];await place(ids,x,y);const snaps=await connect();assert.ok(snaps.every(s=>s.monsters[0].hp===0&&s.explorationCleared.length===i));(i%2===0?a:b).send({type:'exploration_objective',objectiveId:id});for(const p of [a,b]){const e=await p.wait(m=>m.kind==='exploration_objective'&&m.objectiveId===id);assert.deepEqual(e.completed,objectives.slice(0,i+1).map(o=>o[0]));}console.log('PASS shared '+id);}
 await Promise.all([a.close(),b.close()]);const snaps=await connect();assert.ok(snaps.every(s=>s.explorationCleared.length===4&&s.monsters[0].hp===0));
 a.send({type:'exploration_objective',objectiveId:'cassien_resurrection'});await a.wait(m=>m.reason==='objective_already_complete');
 const q=await pool.query("SELECT p.xp::int AS xp,c.balance::int AS gold,k.balance::int AS crystals FROM players p JOIN player_currencies c ON c.player_id=p.id AND c.currency_id='gold' JOIN player_currencies k ON k.player_id=p.id AND k.currency_id='crystals' WHERE p.id=ANY($1::uuid[])",[ids]);assert.deepEqual(q.rows,[{xp:140,gold:180,crystals:20},{xp:140,gold:180,crystals:20}]);
 console.log('PASS reconnect restored resurrection and exact wallet totals');
 const credits=await pool.query("SELECT victories,shared_victories,encounter_credits FROM online_daily_quests WHERE player_id=ANY($1::uuid[])",[ids]);
 assert.equal(credits.rows.length,2);
 assert.ok(credits.rows.every(r=>r.victories===1&&r.shared_victories===1&&r.encounter_credits.length===1&&r.encounter_credits[0]==='cassien'));
 console.log('PASS Cassien credited exactly once for both contributors after reconnect and rejected replay');

}catch(e){console.error('FAIL',e);process.exitCode=1;}finally{for(const s of sockets)s.terminate();if(lobby){for(const t of tokens.slice().reverse()){try{await call(`/v1/co-op/lobbies/${lobby}/leave`,{},t);}catch{}}}await app.close();if(lobby)await pool.query('DELETE FROM co_op_lobbies WHERE id=$1',[lobby]);await pool.query('DELETE FROM accounts WHERE email = ANY($1)',[emails]);await pool.end();console.log('Test fixtures cleaned');}
