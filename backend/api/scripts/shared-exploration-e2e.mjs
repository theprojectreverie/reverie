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
import {dailyQuestRoutes} from '../src/routes/daily-quests.ts';
import {socialRoutes} from '../src/routes/social.ts';
import assert from 'node:assert/strict';
assert.ok(['127.0.0.1','localhost','[::1]'].includes(new URL(config.DATABASE_URL).hostname));
const app=Fastify({logger:false}), suffix=randomBytes(5).toString('hex'), names=[`QaA${suffix}`,`QaB${suffix}`], emails=names.map(n=>n.toLowerCase()+'@example.test'), tokens=[], sockets=[], lobbies=[];
const sleep=ms=>new Promise(r=>setTimeout(r,ms));
async function call(path,body,token){const r=await app.inject({method:'POST',url:path,payload:body,headers:token?{authorization:`Bearer ${token}`}:{}});assert.ok(r.statusCode<300,`${path}: ${r.statusCode} ${r.body}`);return r.json();}
function peer(url,token){const ws=new WebSocket(url,{headers:{authorization:`Bearer ${token}`}});sockets.push(ws);const messages=[];ws.on('message',raw=>messages.push(JSON.parse(String(raw))));return {ws,async wait(fn){const end=Date.now()+7000;while(Date.now()<end){const i=messages.findIndex(fn);if(i>=0)return messages.splice(i,1)[0];await sleep(10);}throw new Error('Timed out waiting for message');},send(data){ws.send(JSON.stringify(data));},async close(){if(ws.readyState===WebSocket.CLOSED)return;await new Promise(r=>{ws.once('close',r);ws.close();});}};}
async function place(lobby,id,x,y){const seq=(await pool.query("UPDATE co_op_lobbies SET next_event_sequence=next_event_sequence+1 WHERE id=$1 RETURNING next_event_sequence-1 AS seq",[lobby])).rows[0].seq;await pool.query("INSERT INTO co_op_world_events(lobby_id,sequence,event_type,actor_player_id,payload) VALUES($1,$2,'position',$3,$4::jsonb)",[lobby,seq,id,JSON.stringify({x,y})]);}
try{
 await app.register(jwt,{secret:config.JWT_SECRET});await app.register(websocket);await app.register(authRoutes,{prefix:'/v1/auth'});await app.register(coopRoutes,{prefix:'/v1/co-op'});await app.register(realtimeRoutes,{prefix:'/v1'});await app.register(dailyQuestRoutes,{prefix:'/v1/daily-quests'});await app.register(socialRoutes,{prefix:'/v1/social'});await app.listen({host:'127.0.0.1',port:0});
 for(let i=0;i<2;i++){const password=randomBytes(16).toString('hex');await call('/v1/auth/register',{email:emails[i],playerName:names[i],password});tokens.push((await call('/v1/auth/login',{playerName:names[i],password})).accessToken);}
 for(const [region,objectives] of [['six_zone_willow_fields',[['willow_bridge',900,1700],['willow_ruins',1710,1300]]],['six_zone_elderwood_grove',[['elderwood_memorial',-700,1370],['elderwood_pillar',760,1960]]]]){
 const created=await call('/v1/co-op/lobbies',{regionId:region,maxMembers:4},tokens[0]);const lobby=created.lobbyId;lobbies.push(lobby);await call('/v1/co-op/lobbies/join',{inviteCode:created.inviteCode},tokens[1]);
 const url=`ws://127.0.0.1:${app.server.address().port}/v1/realtime?lobbyId=${lobby}`;
 let a,b;let ids=[];
 async function connect(){a=peer(url,tokens[0]);b=peer(url,tokens[1]);const c=await Promise.all([a.wait(m=>m.type==='connected'),b.wait(m=>m.type==='connected')]);ids=c.map(m=>m.playerId);return Promise.all([a.wait(m=>m.type==='snapshot'),b.wait(m=>m.type==='snapshot')]);}
 let snapshots=await connect();assert.ok(snapshots.every(s=>s.explorationCleared.length===0));
 const request=(p,id)=>p.send({type:'exploration_objective',objectiveId:id});
 request(a,'bogus');await a.wait(m=>m.type==='rejected'&&m.reason==='unknown_objective');
 request(a,objectives[1][0]);await a.wait(m=>m.type==='rejected'&&m.reason==='objective_order_required');
 request(a,objectives[0][0]);await a.wait(m=>m.type==='rejected'&&m.reason==='objective_proximity_required');
 console.log('PASS '+region+' invalid, remote and out-of-order requests rejected');
 await Promise.all([a.close(),b.close()]);await place(lobby,ids[0],...objectives[0].slice(1));await place(lobby,ids[1],...objectives[0].slice(1));await connect();
 request(a,objectives[0][0]);request(b,objectives[0][0]);
 for(const p of [a,b]){const event=await p.wait(m=>m.kind==='exploration_objective');assert.deepEqual(event.completed,[objectives[0][0]]);}
 const count=await pool.query("SELECT count(*)::int AS count FROM co_op_world_events WHERE lobby_id=$1 AND payload->>'kind'='exploration_objective'",[lobby]);assert.equal(count.rows[0].count,1);console.log('PASS simultaneous requests create exactly one shared objective event');
 await Promise.all([a.close(),b.close()]);await place(lobby,ids[1],...objectives[1].slice(1));snapshots=await connect();assert.ok(snapshots.every(s=>s.explorationCleared.length===1));request(b,objectives[1][0]);
 for(const p of [a,b]){const event=await p.wait(m=>m.kind==='exploration_objective'&&m.objectiveId===objectives[1][0]);assert.deepEqual(event.completed,objectives.map(o=>o[0]));}
 await Promise.all([a.close(),b.close()]);snapshots=await connect();assert.ok(snapshots.every(s=>JSON.stringify(s.explorationCleared)===JSON.stringify(objectives.map(o=>o[0]))));console.log('PASS '+region+' both members contribute; complete state restored on reconnect');
 await Promise.all([a.close(),b.close()]);for(const t of tokens.slice().reverse())await call(`/v1/co-op/lobbies/${lobby}/leave`,{},t);
 }
 const id=(await pool.query("SELECT id FROM players WHERE name=$1",[names[1]])).rows[0].id;
 const achievements=async()=> (await app.inject({method:'GET',url:'/v1/daily-quests/achievements',headers:{authorization:'Bearer '+tokens[1]}})).json().rows;
 const claim=async(id)=>app.inject({method:'POST',url:'/v1/daily-quests/achievements/claim',headers:{authorization:'Bearer '+tokens[1]},payload:{id}});
 let rows=await achievements();
 const row=(key)=>rows.find(x=>x.id===key);
 assert.equal(row('landmark_discoverer').progress,2);
 assert.equal(row('regional_explorer').progress,2);
 assert.equal(row('legendary_collection').can_claim,false);
 assert.equal((await claim('mythic_collection')).statusCode,409);
 const expectedSeasonal=(await pool.query("SELECT count(DISTINCT (payload->>'regionId',payload->>'objectiveId'))::int AS count FROM co_op_world_events WHERE actor_player_id=$1 AND event_type='interaction' AND payload->>'kind'='exploration_objective'",[id])).rows[0].count;
 assert.ok(expectedSeasonal>=2&&expectedSeasonal<=4);
 // Purge completed expedition logs; permanent exploration achievements must persist.
 for(const lobby of lobbies)await pool.query("DELETE FROM co_op_lobbies WHERE id=$1",[lobby]);
 rows=await achievements();
 assert.equal(row('regional_explorer').can_claim,true);
 const seasonal=async()=> (await app.inject({method:'GET',url:'/v1/social/leaderboard?category=exploration&period=monthly',headers:{authorization:'Bearer '+tokens[1]}})).json().rows.find(x=>x.self).score;
 assert.equal(await seasonal(),expectedSeasonal);
 await pool.query("INSERT INTO online_season_exploration(player_id,season_start,region_id,objective_id) SELECT player_id,season_start,region_id,objective_id FROM online_season_exploration WHERE player_id=$1 ON CONFLICT DO NOTHING",[id]);
 assert.equal(await seasonal(),expectedSeasonal);
 console.log('PASS real monthly exploration credits survive expedition deletion and reject repeated objectives');

 // Repeat completion is protected by the permanent unique key.
 const existing=(await pool.query("SELECT region_id,objective_id FROM online_achievement_exploration WHERE player_id=$1",[id])).rows;
 for(const e of existing)await pool.query("INSERT INTO online_achievement_exploration(player_id,region_id,objective_id) VALUES($1,$2,$3) ON CONFLICT DO NOTHING",[id,e.region_id,e.objective_id]);
 assert.equal((await pool.query("SELECT count(*)::int AS count FROM online_achievement_exploration WHERE player_id=$1",[id])).rows[0].count,existing.length);
 // Isolated QA roster: retired cards, unknown IDs and copies do not count as distinct playable characters.
 await pool.query("INSERT INTO owned_characters(player_id,char_id,dupes) SELECT $1,unnest($2::text[]),10 ON CONFLICT DO NOTHING",[id,['kael_epic','ravienna_rare','kael_legendary','gerald_legendary']]);
 rows=await achievements();assert.equal(row('legendary_collection').progress,2);assert.equal(row('mythic_collection').progress,0);
 await pool.query("INSERT INTO owned_characters(player_id,char_id) SELECT $1,unnest($2::text[]) ON CONFLICT DO NOTHING",[id,['lilith_legendary','ravienna_mythic']]);
 rows=await achievements();assert.equal(row('legendary_collection').can_claim,true);assert.equal(row('mythic_collection').can_claim,true);
 const batch=()=>app.inject({method:'POST',url:'/v1/daily-quests/achievements/claim-all',headers:{authorization:'Bearer '+tokens[1]},payload:{}});
 const claims=await Promise.all([batch(),batch()]);assert.deepEqual(claims.map(x=>x.statusCode).sort(),[200,409]);
 const awards=claims.find(x=>x.statusCode===200).json().awards;
 assert.equal(awards.length,4);assert.equal(awards.reduce((a,x)=>a+x.gold,0),3300);assert.equal(awards.reduce((a,x)=>a+x.crystals,0),200);
 const wallet=(await app.inject({method:'GET',url:'/v1/auth/wallet',headers:{authorization:'Bearer '+tokens[1]}})).json();
 assert.equal(Number(wallet.gold),3300);assert.equal(Number(wallet.currencies.crystals),200);
 const profile=(await app.inject({method:'GET',url:'/v1/social/profile',headers:{authorization:'Bearer '+tokens[1]}})).json();
 assert.equal(profile.achievementCount,4);assert.equal(profile.titles.length,15);
 assert.equal((await app.inject({method:'POST',url:'/v1/social/title',headers:{authorization:'Bearer '+tokens[1]},payload:{titleId:'mythic_collection'}})).json().title,'Mythic Collector');
 rows=await achievements();assert.ok(['landmark_discoverer','regional_explorer','legendary_collection','mythic_collection'].every(key=>row(key).claimed));
 console.log('PASS permanent distinct exploration, historical log deletion, retired-card exclusion, unique collection, all four achievement claims, exact wallet and title unlocks');
}catch(e){console.error('FAIL',e);process.exitCode=1;}finally{for(const s of sockets)s.terminate();for(const l of lobbies){for(const t of tokens.slice().reverse()){try{await call(`/v1/co-op/lobbies/${l}/leave`,{},t);}catch{}}}await app.close();for(const l of lobbies)await pool.query('DELETE FROM co_op_lobbies WHERE id=$1',[l]);await pool.query('DELETE FROM accounts WHERE email = ANY($1)',[emails]);await pool.end();console.log('Test fixtures cleaned');}
