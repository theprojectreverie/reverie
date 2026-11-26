import Fastify from 'fastify';
import jwt from '@fastify/jwt';
import websocket from '@fastify/websocket';
import WebSocket from 'ws';
import {randomBytes} from 'node:crypto';
import {readFileSync} from 'node:fs';
import {config} from '../src/config.ts';
import {pool} from '../src/db.ts';
import {authRoutes} from '../src/routes/auth.ts';
import {coopRoutes} from '../src/routes/coop.ts';
import {realtimeRoutes} from '../src/routes/realtime.ts';
import assert from 'node:assert/strict';
assert.ok(['127.0.0.1','localhost','[::1]'].includes(new URL(config.DATABASE_URL).hostname));
const data=JSON.parse(readFileSync(new URL('../../../resources/data/six_zone_expeditions.json',import.meta.url),'utf8'));
const zones=Object.keys(data), route=[...zones,...zones.slice(0,-1).reverse()];
const app=Fastify({logger:false}), suffix=randomBytes(5).toString('hex'), names=[`QaA${suffix}`,`QaB${suffix}`], emails=names.map(n=>n.toLowerCase()+'@example.test'), tokens=[], sockets=[];
let lobby='';
const sleep=ms=>new Promise(r=>setTimeout(r,ms));
async function call(path,body,token){const r=await app.inject({method:'POST',url:path,payload:body,headers:token?{authorization:`Bearer ${token}`}:{}});assert.ok(r.statusCode<300,`${path}: ${r.statusCode}`);return r.json();}
function peer(url,token){const ws=new WebSocket(url,{headers:{authorization:`Bearer ${token}`}});sockets.push(ws);const messages=[];ws.on('message',raw=>messages.push(JSON.parse(String(raw))));return {ws,async wait(fn){const end=Date.now()+7000;while(Date.now()<end){const i=messages.findIndex(fn);if(i>=0)return messages.splice(i,1)[0];await sleep(10);}throw new Error('Timed out waiting for message');},send(data){ws.send(JSON.stringify(data));},async close(){if(ws.readyState===WebSocket.CLOSED)return;await new Promise(r=>{ws.once('close',r);ws.close();});}};}
async function place(playerId,x,y){const seq=(await pool.query("UPDATE co_op_lobbies SET next_event_sequence=next_event_sequence+1 WHERE id=$1 RETURNING next_event_sequence-1 AS seq",[lobby])).rows[0].seq;await pool.query("INSERT INTO co_op_world_events(lobby_id,sequence,event_type,actor_player_id,payload) VALUES($1,$2,'position',$3,$4::jsonb)",[lobby,seq,playerId,JSON.stringify({x,y})]);}
try{
 await app.register(jwt,{secret:config.JWT_SECRET});await app.register(websocket);await app.register(authRoutes,{prefix:'/v1/auth'});await app.register(coopRoutes,{prefix:'/v1/co-op'});await app.register(realtimeRoutes,{prefix:'/v1'});await app.listen({host:'127.0.0.1',port:0});
 for(let i=0;i<2;i++){const password=randomBytes(16).toString('hex');await call('/v1/auth/register',{email:emails[i],playerName:names[i],password});tokens.push((await call('/v1/auth/login',{playerName:names[i],password})).accessToken);}
 const created=await call('/v1/co-op/lobbies',{regionId:route[0],maxMembers:4},tokens[0]);lobby=created.lobbyId;await call('/v1/co-op/lobbies/join',{inviteCode:created.inviteCode},tokens[1]);
 const url=`ws://127.0.0.1:${app.server.address().port}/v1/realtime?lobbyId=${lobby}`;
 let a=peer(url,tokens[0]),b=peer(url,tokens[1]);const ca=await a.wait(m=>m.type==='connected');await b.wait(m=>m.type==='connected');
 let sa=await a.wait(m=>m.type==='snapshot');await b.wait(m=>m.type==='snapshot');
 b.send({type:'region_transition',regionId:route[1]});await b.wait(m=>m.type==='rejected'&&m.reason==='leader_or_region_required');
 a.send({type:'region_transition',regionId:route[1]});await a.wait(m=>m.type==='rejected'&&m.reason==='portal_proximity_required');
 console.log('PASS nonleader and remote portal rejection');
 for(let i=1;i<route.length;i++){
  const from=route[i-1],to=route[i], portal=data[from].portals[to];assert.ok(portal);
  await place(ca.playerId,...portal);
  const cursor=sa.sequence;
  a.send({type:'region_transition',regionId:to});const e=await a.wait(m=>m.type==='region_transition'&&m.regionId===to);await b.wait(m=>m.type==='region_transition'&&m.regionId===to);
  b.send({type:'resume',lastSequence:cursor});const recovered=await b.wait(m=>m.type==='snapshot'&&m.requires_resync===true);assert.ok(recovered.members.every(m=>m.region_id===to));assert.equal(recovered.sequence,e.sequence);assert.ok(recovered.members.every(m=>m.x===data[to].spawn[0]&&m.y===data[to].spawn[1]));
  await Promise.all([a.close(),b.close()]);
  a=peer(url,tokens[0]);b=peer(url,tokens[1]);await a.wait(m=>m.type==='connected');await b.wait(m=>m.type==='connected');sa=await a.wait(m=>m.type==='snapshot');const sb=await b.wait(m=>m.type==='snapshot');for(const s of [sa,sb])assert.ok(s.members.length===2&&s.members.every(m=>m.region_id===to&&m.x===data[to].spawn[0]&&m.y===data[to].spawn[1]));
  console.log('PASS '+data[from].label+' -> '+data[to].label+'; shared transition, replay recovery and reconnect spawn');
 }
}catch(e){console.error('FAIL',e);process.exitCode=1;}finally{for(const s of sockets)s.terminate();if(lobby){for(const t of tokens.slice().reverse()){try{await call(`/v1/co-op/lobbies/${lobby}/leave`,{},t);}catch{}}}await app.close();if(lobby)await pool.query('DELETE FROM co_op_lobbies WHERE id=$1',[lobby]);await pool.query('DELETE FROM accounts WHERE email = ANY($1)',[emails]);await pool.end();console.log('Test fixtures cleaned');}
