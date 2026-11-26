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
const app=Fastify({logger:false});
const suffix=randomBytes(5).toString('hex');
const names=[`QaA${suffix}`,`QaB${suffix}`];
const emails=names.map(n=>`${n.toLowerCase()}@example.test`);
const sockets=[];const tokens=[];let lobby='';
const region='six_zone_royal_gardens';
async function call(path,body,token){const r=await app.inject({method:'POST',url:path,payload:body,headers:token?{authorization:`Bearer ${token}`}:{}});assert.ok(r.statusCode<300,`${path}: ${r.statusCode} ${r.json().error??''}`);return r.json();}
function peer(url,token){const ws=new WebSocket(url,{headers:{authorization:`Bearer ${token}`}});sockets.push(ws);const messages=[];ws.on('message',raw=>messages.push(JSON.parse(String(raw))));return {ws,async wait(fn){const end=Date.now()+7000;while(Date.now()<end){const i=messages.findIndex(fn);if(i>=0)return messages.splice(i,1)[0];await new Promise(r=>setTimeout(r,20));}throw new Error('Timed out waiting for message');},send(data){ws.send(JSON.stringify(data));}};}
try {
 await app.register(jwt,{secret:config.JWT_SECRET});await app.register(websocket);await app.register(authRoutes,{prefix:'/v1/auth'});await app.register(coopRoutes,{prefix:'/v1/co-op'});await app.register(realtimeRoutes,{prefix:'/v1'});await app.listen({host:'127.0.0.1',port:0});
 for(let i=0;i<2;i++){const password=randomBytes(16).toString('hex');await call('/v1/auth/register',{email:emails[i],playerName:names[i],password});tokens.push((await call('/v1/auth/login',{playerName:names[i],password})).accessToken);}
 const created=await call('/v1/co-op/lobbies',{regionId:region,maxMembers:4},tokens[0]);lobby=created.lobbyId;await call('/v1/co-op/lobbies/join',{inviteCode:created.inviteCode},tokens[1]);console.log('PASS two independent registered and authenticated accounts joined the same lobby');
 const url=`ws://127.0.0.1:${app.server.address().port}/v1/realtime?lobbyId=${lobby}`;const a=peer(url,tokens[0]),b=peer(url,tokens[1]);const ca=await a.wait(m=>m.type==='connected'),cb=await b.wait(m=>m.type==='connected');assert.notEqual(ca.playerId,cb.playerId);const sa=await a.wait(m=>m.type==='snapshot'),sb=await b.wait(m=>m.type==='snapshot');for(const s of [sa,sb]){assert.equal(s.members.length,2);assert.ok(s.members.every(m=>m.x===-1320&&m.y===2325));}console.log('PASS both clients received correct Royal Gardens spawn and two-player roster');
 await new Promise(r=>setTimeout(r,250));a.send({type:'position',regionId:region,x:-1300,y:2325});await b.wait(m=>m.type==='position'&&m.playerId===ca.playerId&&m.x===-1300);b.send({type:'position',regionId:region,x:-1320,y:2305});await a.wait(m=>m.type==='position'&&m.playerId===cb.playerId&&m.y===2305);console.log('PASS bidirectional live movement over authenticated WebSockets');
 a.send({type:'position',regionId:'royal_gate',x:-1300,y:2325});await a.wait(m=>m.type==='rejected'&&m.reason==='region_mismatch');a.send({type:'position',regionId:region,x:9000,y:2325});await a.wait(m=>m.type==='rejected'&&m.reason==='region_bounds');console.log('PASS server rejects wrong region and out-of-bounds movement');
} catch(e){console.error('FAIL',e.message);process.exitCode=1;} finally {for(const s of sockets)s.terminate();if(lobby){for(const t of tokens.slice().reverse()){try{await call(`/v1/co-op/lobbies/${lobby}/leave`,{},t);}catch{}}}await app.close();if(lobby)await pool.query('DELETE FROM co_op_lobbies WHERE id=$1',[lobby]);await pool.query('DELETE FROM accounts WHERE email = ANY($1)',[emails]);await pool.end();console.log('Test fixtures cleaned');}