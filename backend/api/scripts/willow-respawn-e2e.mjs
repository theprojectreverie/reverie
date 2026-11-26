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
assert.ok(['localhost','127.0.0.1','[::1]'].includes(new URL(config.DATABASE_URL).hostname));const app=Fastify({logger:false});
const suffix=randomBytes(5).toString('hex');
const names=[`QaA${suffix}`,`QaB${suffix}`];
const emails=names.map(n=>`${n.toLowerCase()}@example.test`);
const sockets=[];const tokens=[];let lobby='';
const region='six_zone_willow_fields';
async function call(path,body,token){const r=await app.inject({method:'POST',url:path,payload:body,headers:token?{authorization:`Bearer ${token}`}:{}});assert.ok(r.statusCode<300,`${path}: ${r.statusCode} ${r.json().error??''}`);return r.json();}
function peer(url,token){const ws=new WebSocket(url,{headers:{authorization:`Bearer ${token}`}});sockets.push(ws);const messages=[];ws.on('message',raw=>messages.push(JSON.parse(String(raw))));return {ws,async wait(fn){const end=Date.now()+7000;while(Date.now()<end){const i=messages.findIndex(fn);if(i>=0)return messages.splice(i,1)[0];await new Promise(r=>setTimeout(r,20));}throw new Error('Timed out waiting for message');},send(data){ws.send(JSON.stringify(data));}};}
try {
 await app.register(jwt,{secret:config.JWT_SECRET});await app.register(websocket);await app.register(authRoutes,{prefix:'/v1/auth'});await app.register(coopRoutes,{prefix:'/v1/co-op'});await app.register(realtimeRoutes,{prefix:'/v1'});await app.listen({host:'127.0.0.1',port:0});
 for(let i=0;i<2;i++){const password=randomBytes(16).toString('hex');await call('/v1/auth/register',{email:emails[i],playerName:names[i],password});tokens.push((await call('/v1/auth/login',{playerName:names[i],password})).accessToken);}
 const created=await call('/v1/co-op/lobbies',{regionId:region,maxMembers:4},tokens[0]);lobby=created.lobbyId;await call('/v1/co-op/lobbies/join',{inviteCode:created.inviteCode},tokens[1]);console.log('PASS two independent registered and authenticated accounts joined the same lobby');
 const url=`ws://127.0.0.1:${app.server.address().port}/v1/realtime?lobbyId=${lobby}`;const a=peer(url,tokens[0]);let b=peer(url,tokens[1]);const ca=await a.wait(m=>m.type==='connected'),cb=await b.wait(m=>m.type==='connected');assert.notEqual(ca.playerId,cb.playerId);const sa=await a.wait(m=>m.type==='snapshot'),sb=await b.wait(m=>m.type==='snapshot');for(const s of [sa,sb]){assert.equal(s.members.length,2);assert.ok(s.members.every(m=>m.x===-2450&&m.y===1370));}console.log('PASS both clients received correct Willow Fields spawn and two-player roster');
 await new Promise(r=>setTimeout(r,250));a.send({type:'position',regionId:region,x:-2430,y:1370});await b.wait(m=>m.type==='position'&&m.playerId===ca.playerId&&m.x===-2430);b.send({type:'position',regionId:region,x:-2450,y:1350});await a.wait(m=>m.type==='position'&&m.playerId===cb.playerId&&m.y===1350);console.log('PASS bidirectional live movement over authenticated WebSockets');
 a.send({type:'position',regionId:'royal_gate',x:-2430,y:1370});await a.wait(m=>m.type==='rejected'&&m.reason==='region_mismatch');a.send({type:'position',regionId:region,x:9000,y:1370});await a.wait(m=>m.type==='rejected'&&m.reason==='region_bounds');console.log('PASS server rejects wrong region and out-of-bounds movement');
 const monsterId='willow_slime_1';
 for(let i=1;i<=4;i++){
   await new Promise(r=>setTimeout(r,250));
   const x=-2430+i*20,y=1370;
   a.send({type:'position',regionId:region,x,y});
   await b.wait(m=>m.type==='position'&&m.playerId===ca.playerId&&m.x===x);
 }
 async function hit(expected){
   await new Promise(r=>setTimeout(r,550));
   a.send({type:'monster_attack',monsterId});
   const x=await a.wait(m=>m.type==='interaction'&&m.monsterId===monsterId);
   const y=await b.wait(m=>m.type==='interaction'&&m.monsterId===monsterId);
   assert.equal(x.hp,expected);assert.equal(y.hp,expected);
   assert.equal(x.deadUntil,y.deadUntil);return x;
 }
 for(const hp of [75,50,25])await hit(hp);
 const dead=await hit(0);
 assert.ok(dead.deadUntil>Date.now()+13000);
 assert.equal(dead.rewards.length,1);
 await new Promise(r=>setTimeout(r,550));
 a.send({type:'monster_attack',monsterId});
 await a.wait(m=>m.type==='rejected'&&m.reason==='monster_defeated');
  console.log('PASS both clients agree on defeat, reward, and dead-time rejection');
 async function reconnectObserver(){
   const closed=new Promise(resolve=>b.ws.once('close',resolve));
   b.ws.terminate();await closed;
   b=peer(url,tokens[1]);
   await b.wait(m=>m.type==='connected');
   const snapshot=await b.wait(m=>m.type==='snapshot');
   return snapshot.monsters.find(m=>m.monsterId===monsterId);
 }
 const before=await reconnectObserver();
 assert.equal(before.hp,0);assert.equal(before.deadUntil,dead.deadUntil);
 assert.deepEqual(before.rewards,[]);
 console.log('PASS reconnect during dead time preserves the countdown without replaying rewards');
 await new Promise(r=>setTimeout(r,Math.max(0,dead.deadUntil-Date.now()+300)));
  const after=await reconnectObserver();
 assert.equal(after.hp,100);assert.equal(after.deadUntil,0);
 assert.deepEqual(after.rewards,[]);
 console.log('PASS reconnect after expiry receives a full-health mob without stale rewards');
 await hit(75);
 for(const hp of [50,25])await hit(hp);
 const deadAgain=await hit(0);
 assert.equal(deadAgain.rewards.length,1);
 assert.ok(deadAgain.deadUntil>dead.deadUntil);
 console.log('PASS full HP after expiry and rewards on second legitimate defeat');
} catch(e){console.error('FAIL',e.message);process.exitCode=1;} finally {for(const s of sockets)s.terminate();if(lobby){for(const t of tokens.slice().reverse()){try{await call(`/v1/co-op/lobbies/${lobby}/leave`,{},t);}catch{}}}await app.close();if(lobby)await pool.query('DELETE FROM co_op_lobbies WHERE id=$1',[lobby]);await pool.query('DELETE FROM accounts WHERE email = ANY($1)',[emails]);await pool.end();console.log('Test fixtures cleaned');}