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
 const created=await call('/v1/co-op/lobbies',{regionId:'six_zone_royal_gate',maxMembers:4},tokens[0]);lobby=created.lobbyId;await call('/v1/co-op/lobbies/join',{inviteCode:created.inviteCode},tokens[1]);
 const ids=(await pool.query("SELECT player_id FROM co_op_lobby_members WHERE lobby_id=$1 ORDER BY joined_at",[lobby])).rows.map(x=>x.player_id);
 const url=`ws://127.0.0.1:${app.server.address().port}/v1/realtime?lobbyId=${lobby}`;
 let a,b;
 async function connect(){a=peer(url,tokens[0]);b=peer(url,tokens[1]);await a.wait(m=>m.type==='connected');await b.wait(m=>m.type==='connected');return Promise.all([a.wait(m=>m.type==='snapshot'),b.wait(m=>m.type==='snapshot')]);}
 await connect();
 a.send({type:'monster_attack',monsterId:'rose_slime_garden_1'});await a.wait(m=>m.type==='rejected'&&m.reason==='unknown_monster');
 a.send({type:'monster_attack',monsterId:'royal_gate_patrol_1'});await a.wait(m=>m.type==='rejected'&&m.reason==='attack_out_of_range');console.log('PASS wrong-region and out-of-range strikes rejected');
 for(const [index,coords] of [[1,[-65,1200]],[2,[75,1840]]]){
  await Promise.all([a.close(),b.close()]);await place(ids,...coords);await connect();
  const monsterId='royal_gate_patrol_'+index;
  for(let i=0;i<5;i++){await sleep(310);(i%2===0?a:b).send({type:'monster_attack',monsterId});const expected=Math.max(0,120-(i+1)*25);const ev=await a.wait(m=>m.type==='interaction'&&m.monsterId===monsterId&&m.hp===expected);await b.wait(m=>m.type==='interaction'&&m.monsterId===monsterId&&m.hp===expected);assert.equal(ev.maxHp,120);if(expected===0){assert.equal(ev.rewards.length,2);assert.ok(ev.rewards.every(r=>r.gold===25&&r.xp===18&&r.items.moonpetal===1));}}
  await sleep(550);a.send({type:'monster_attack',monsterId});await a.wait(m=>m.type==='rejected'&&m.reason==='monster_defeated');
  await Promise.all([a.close(),b.close()]);const snaps=await connect();for(const s of snaps){assert.equal(s.patrolCleared.length,index);assert.ok(s.monsters.some(m=>m.monsterId===monsterId&&m.hp===0));}
  console.log('PASS patrol '+index+' shared health, two payouts, duplicate rejection and reconnect progress');
 }
 const q=await pool.query("SELECT p.xp::int AS xp,c.balance::int AS gold,i.quantity::int AS petals FROM players p JOIN player_currencies c ON c.player_id=p.id AND c.currency_id='gold' JOIN inventory_items i ON i.player_id=p.id AND i.item_id='moonpetal' WHERE p.id=ANY($1::uuid[])",[ids]);assert.deepEqual(q.rows,[{xp:36,gold:50,petals:2},{xp:36,gold:50,petals:2}]);console.log('PASS exact persistent wallet totals');
 await sleep(15050);await Promise.all([a.close(),b.close()]);const snaps=await connect();for(const s of snaps){assert.equal(s.patrolCleared.length,2);assert.ok(s.monsters.every(m=>m.hp===120&&m.deadUntil===0));}console.log('PASS both patrol enemies respawn with 120 HP; completed objective retained');
}catch(e){console.error('FAIL',e);process.exitCode=1;}finally{for(const s of sockets)s.terminate();if(lobby){for(const t of tokens.slice().reverse()){try{await call(`/v1/co-op/lobbies/${lobby}/leave`,{},t);}catch{}}}await app.close();if(lobby)await pool.query('DELETE FROM co_op_lobbies WHERE id=$1',[lobby]);await pool.query('DELETE FROM accounts WHERE email = ANY($1)',[emails]);await pool.end();console.log('Test fixtures cleaned');}
