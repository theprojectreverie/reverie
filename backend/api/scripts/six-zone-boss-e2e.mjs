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
const region='six_zone_ruined_tower';
async function call(path,body,token){const r=await app.inject({method:'POST',url:path,payload:body,headers:token?{authorization:`Bearer ${token}`}:{}});assert.ok(r.statusCode<300,`${path}: ${r.statusCode} ${r.json().error??''}`);return r.json();}
function peer(url,token){const ws=new WebSocket(url,{headers:{authorization:`Bearer ${token}`}});sockets.push(ws);const messages=[];ws.on('message',raw=>messages.push(JSON.parse(String(raw))));return {ws,async wait(fn){const end=Date.now()+7000;while(Date.now()<end){const i=messages.findIndex(fn);if(i>=0)return messages.splice(i,1)[0];await new Promise(r=>setTimeout(r,20));}throw new Error('Timed out waiting for message');},send(data){ws.send(JSON.stringify(data));}};}
try {
 await app.register(jwt,{secret:config.JWT_SECRET});await app.register(websocket);await app.register(authRoutes,{prefix:'/v1/auth'});await app.register(coopRoutes,{prefix:'/v1/co-op'});await app.register(realtimeRoutes,{prefix:'/v1'});await app.listen({host:'127.0.0.1',port:0});
 for(let i=0;i<2;i++){const password=randomBytes(16).toString('hex');await call('/v1/auth/register',{email:emails[i],playerName:names[i],password});tokens.push((await call('/v1/auth/login',{playerName:names[i],password})).accessToken);}
 const created=await call('/v1/co-op/lobbies',{regionId:region,maxMembers:4},tokens[0]);lobby=created.lobbyId;await call('/v1/co-op/lobbies/join',{inviteCode:created.inviteCode},tokens[1]);console.log('PASS two independent registered and authenticated accounts joined the same lobby');
  const members=(await pool.query("SELECT player_id FROM co_op_lobby_members WHERE lobby_id=$1 ORDER BY joined_at",[lobby])).rows;
 for(const member of members){const seq=(await pool.query("UPDATE co_op_lobbies SET next_event_sequence=next_event_sequence+1 WHERE id=$1 RETURNING next_event_sequence-1 AS seq",[lobby])).rows[0].seq;await pool.query("INSERT INTO co_op_world_events(lobby_id,sequence,event_type,actor_player_id,payload) VALUES($1,$2,'position',$3,$4::jsonb)",[lobby,seq,member.player_id,JSON.stringify({x:0,y:1050})]);}
 const url=`ws://127.0.0.1:${app.server.address().port}/v1/realtime?lobbyId=${lobby}`;const a=peer(url,tokens[0]),b=peer(url,tokens[1]);const ca=await a.wait(m=>m.type==='connected'),cb=await b.wait(m=>m.type==='connected');await a.wait(m=>m.type==='snapshot');await b.wait(m=>m.type==='snapshot');
 const phases=new Set();
 for(let i=0;i<18;i++){const p=i%2===0?a:b;await new Promise(r=>setTimeout(r,280));p.send({type:'monster_attack',monsterId:'revienna_encounter'});const expected=1800-(i+1)*100;for(const client of [a,b]){const event=await client.wait(m=>m.type==='interaction'&&m.monsterId==='revienna_encounter'&&m.hp===expected);phases.add(event.phase);}}
 assert.deepEqual([...phases],[1,2,3]);console.log('PASS shared 1800 HP and all three Revienna phases');
 await new Promise(r=>setTimeout(r,550));a.send({type:'monster_attack',monsterId:'revienna_encounter'});await a.wait(m=>m.type==='rejected'&&m.reason==='monster_defeated');
 const q=await pool.query("SELECT p.xp::int AS xp,c.balance::int AS gold,i.quantity::int AS shards FROM players p JOIN player_currencies c ON c.player_id=p.id AND c.currency_id='gold' JOIN inventory_items i ON i.player_id=p.id AND i.item_id='gothic_shard' WHERE p.id=ANY($1::uuid[])",[[ca.playerId,cb.playerId]]);assert.deepEqual(q.rows,[{xp:3000,gold:2000,shards:4},{xp:3000,gold:2000,shards:4}]);console.log('PASS two individual boss reward payouts and duplicate defeat rejection');
} catch(e){console.error('FAIL',e.message);process.exitCode=1;} finally {for(const s of sockets)s.terminate();if(lobby){for(const t of tokens.slice().reverse()){try{await call(`/v1/co-op/lobbies/${lobby}/leave`,{},t);}catch{}}}await app.close();if(lobby)await pool.query('DELETE FROM co_op_lobbies WHERE id=$1',[lobby]);await pool.query('DELETE FROM accounts WHERE email = ANY($1)',[emails]);await pool.end();console.log('Test fixtures cleaned');}