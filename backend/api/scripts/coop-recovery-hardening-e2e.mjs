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
const db = new URL(config.DATABASE_URL);
assert.ok(['127.0.0.1','localhost','[::1]'].includes(db.hostname), 'local database only');
const app=Fastify({logger:false}), suffix=randomBytes(5).toString('hex'), names=[`QaA${suffix}`,`QaB${suffix}`], emails=names.map(n=>n.toLowerCase()+'@example.test'), tokens=[], sockets=[];
let lobby='';
const sleep=ms=>new Promise(r=>setTimeout(r,ms));
async function call(path,body,token,method='POST'){const r=await app.inject({method,url:path,payload:method==='GET'?undefined:body,headers:token?{authorization:`Bearer ${token}`}:{}});assert.ok(r.statusCode<300,`${path}: ${r.statusCode}`);return r.json();}
function peer(url,token){const ws=new WebSocket(url,{headers:{authorization:`Bearer ${token}`}});sockets.push(ws);const messages=[];ws.on('message',raw=>messages.push(JSON.parse(String(raw))));return {ws,async wait(fn){const end=Date.now()+7000;while(Date.now()<end){const i=messages.findIndex(fn);if(i>=0)return messages.splice(i,1)[0];await sleep(10);}throw new Error('Timed out waiting for message');},send(data){ws.send(JSON.stringify(data));},async close(){if(ws.readyState===WebSocket.CLOSED)return;await new Promise(r=>{ws.once('close',r);ws.close();});}};}
try{
 await app.register(jwt,{secret:config.JWT_SECRET});await app.register(websocket);await app.register(authRoutes,{prefix:'/v1/auth'});await app.register(coopRoutes,{prefix:'/v1/co-op'});await app.register(realtimeRoutes,{prefix:'/v1'});await app.listen({host:'127.0.0.1',port:0});
 for(let i=0;i<2;i++){const password=randomBytes(16).toString('hex');await call('/v1/auth/register',{email:emails[i],playerName:names[i],password});tokens.push((await call('/v1/auth/login',{playerName:names[i],password})).accessToken);}
 const created=await call('/v1/co-op/lobbies',{regionId:'six_zone_ruined_tower',maxMembers:4},tokens[0]);lobby=created.lobbyId;
 await call('/v1/co-op/lobbies/join',{inviteCode:created.inviteCode},tokens[1]);
 const members=(await pool.query("SELECT player_id FROM co_op_lobby_members WHERE lobby_id=$1 ORDER BY joined_at",[lobby])).rows;
 for(const member of members){const seq=(await pool.query("UPDATE co_op_lobbies SET next_event_sequence=next_event_sequence+1 WHERE id=$1 RETURNING next_event_sequence-1 AS seq",[lobby])).rows[0].seq;await pool.query("INSERT INTO co_op_world_events(lobby_id,sequence,event_type,actor_player_id,payload) VALUES($1,$2,'position',$3,$4::jsonb)",[lobby,seq,member.player_id,JSON.stringify({x:0,y:1050})]);}
 const url=`ws://127.0.0.1:${app.server.address().port}/v1/realtime?lobbyId=${lobby}`;
 let a=peer(url,tokens[0]),b=peer(url,tokens[1]);
 const ca=await a.wait(m=>m.type==='connected'),cb=await b.wait(m=>m.type==='connected');
 await a.wait(m=>m.type==='snapshot');await b.wait(m=>m.type==='snapshot');
 a.send({type:'monster_attack',monsterId:'revienna_encounter'});await a.wait(m=>m.type==='interaction'&&m.hp===1700);
 b.send({type:'monster_attack',monsterId:'revienna_encounter'});const special=await b.wait(m=>m.type==='interaction'&&m.hp===1600&&m.warning);
 assert.equal(special.warning.targetId,cb.playerId);
 b.send({type:'monster_attack',monsterId:'revienna_encounter',guard:true});await b.wait(m=>m.type==='interaction'&&m.kind==='boss_guard');
 const b2=peer(url,tokens[1]);await b2.wait(m=>m.type==='connected');const snapshot=await b2.wait(m=>m.type==='snapshot');
 assert.equal(snapshot.monsters[0].warning.guardAcknowledged,true);console.log('PASS guard acknowledgement restored in snapshot');
 await Promise.all([a.close(),b.close(),b2.close()]);
 await sleep(Math.max(0,special.warning.resolveAt-Date.now())+400);
 const resolved=(await pool.query("SELECT payload FROM co_op_world_events WHERE lobby_id=$1 AND payload->>'resolvedSpecial'='Corruption Bolt'",[lobby])).rows;
 assert.equal(resolved.length,1);assert.equal(resolved[0].payload.guarded,true);assert.equal(resolved[0].payload.counterattack.damage,6);console.log('PASS pending special resolves exactly once with no sockets connected');
 a=peer(url,tokens[0]);b=peer(url,tokens[1]);await a.wait(m=>m.type==='connected');await b.wait(m=>m.type==='connected');
 const sa=await a.wait(m=>m.type==='snapshot');assert.equal(sa.monsters[0].hp,1600);assert.equal(sa.monsters[0].warning,null);await b.wait(m=>m.type==='snapshot');console.log('PASS reconnect restores boss HP and resolved warning');
 const closed=new Promise(r=>a.ws.once('close',(code,reason)=>r([code,String(reason)])));
 await call(`/v1/co-op/lobbies/${lobby}/leave`,{},tokens[0]);const close=await Promise.race([closed,sleep(4000).then(()=>null)]);
 assert.deepEqual(close,[1008,'lobby_membership_required']);await b.wait(m=>m.type==='player_left'&&m.playerId===ca.playerId);
 const current=await call('/v1/co-op/lobbies/current',undefined,tokens[1],'GET');assert.equal(current.lobby.leaderPlayerId,cb.playerId);console.log('PASS departed socket revoked and remaining party leader promoted');
 b.send({type:'ping'});await b.wait(m=>m.type==='pong');console.log('PASS remaining party connection survives departure');
}catch(e){console.error('FAIL',e);process.exitCode=1;}finally{for(const s of sockets)s.terminate();if(lobby){for(const t of tokens.slice().reverse()){try{await call(`/v1/co-op/lobbies/${lobby}/leave`,{},t);}catch{}}}await app.close();if(lobby)await pool.query('DELETE FROM co_op_lobbies WHERE id=$1',[lobby]);await pool.query('DELETE FROM accounts WHERE email = ANY($1)',[emails]);await pool.end();console.log('Test fixtures cleaned');}
