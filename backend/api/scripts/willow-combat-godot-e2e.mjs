import Fastify from 'fastify';
import jwt from '@fastify/jwt';
import websocket from '@fastify/websocket';
import WebSocket from 'ws';
import {randomBytes} from 'node:crypto';
import {spawn} from 'node:child_process';
import {fileURLToPath} from 'node:url';
import {config} from '../src/config.ts';
import {pool} from '../src/db.ts';
import {authRoutes} from '../src/routes/auth.ts';
import {coopRoutes} from '../src/routes/coop.ts';
import {realtimeRoutes} from '../src/routes/realtime.ts';
import {socialRoutes} from '../src/routes/social.ts';
import {dailyQuestRoutes,recordOnlineDailyVictory} from '../src/routes/daily-quests.ts';
import assert from 'node:assert/strict';
assert.ok(['localhost','127.0.0.1','[::1]'].includes(new URL(config.DATABASE_URL).hostname));
const region=process.argv[2] ?? "six_zone_willow_fields";
const app=Fastify({logger:false}), suffix=randomBytes(5).toString('hex'), names=[`QaA${suffix}`,`QaB${suffix}`], emails=names.map(n=>`${n.toLowerCase()}@example.test`), passwords=names.map(()=>randomBytes(16).toString('hex')), tokens=[];let lobby='';
async function call(path,body,token){const r=await app.inject({method:'POST',url:path,payload:body,headers:token?{authorization:`Bearer ${token}`}:{}});assert.ok(r.statusCode<300,`${path}: ${r.statusCode} ${r.json().error??''}`);return r.json();}
function worker(i,port){return new Promise((resolve,reject)=>{const root=fileURLToPath(new URL('../../../',import.meta.url));const child=spawn(process.env.QA_GODOT,['--headless','--path',root,'res://tools/qa_coop_willow.tscn'],{cwd:root,env:{...process.env,REVERIE_E2E_DISABLE_LOCAL_SAVE:'1',QA_API:`http://127.0.0.1:${port}`,QA_WS:`ws://127.0.0.1:${port}/v1/realtime`,QA_NAME:names[i],QA_PASSWORD:passwords[i],QA_LOBBY:lobby,QA_REGION:region,QA_ROLE:i===0?'A':'B'}});let output='';child.stdout.on('data',d=>output+=d);child.stderr.on('data',d=>output+=d);const timer=setTimeout(()=>child.kill(),45000);child.on('error',e=>{clearTimeout(timer);reject(e)});child.on('close',code=>{clearTimeout(timer);console.log(`CLIENT ${i+1} EXIT ${code}\n${output}`);resolve(code);});});}
try {await app.register(jwt,{secret:config.JWT_SECRET});await app.register(websocket);await app.register(authRoutes,{prefix:'/v1/auth'});await app.register(coopRoutes,{prefix:'/v1/co-op'});await app.register(realtimeRoutes,{prefix:'/v1'});await app.register(dailyQuestRoutes,{prefix:'/v1/daily-quests'});await app.register(socialRoutes,{prefix:'/v1/social'});await app.listen({host:'127.0.0.1',port:0});for(let i=0;i<2;i++){await call('/v1/auth/register',{email:emails[i],playerName:names[i],password:passwords[i]});tokens.push((await call('/v1/auth/login',{playerName:names[i],password:passwords[i]})).accessToken);}const created=await call('/v1/co-op/lobbies',{regionId:region,maxMembers:4},tokens[0]);lobby=created.lobbyId;await call('/v1/co-op/lobbies/join',{inviteCode:created.inviteCode},tokens[1]);const members=(await pool.query("SELECT player_id FROM co_op_lobby_members WHERE lobby_id=$1",[lobby])).rows;for(const member of members){const seq=(await pool.query("UPDATE co_op_lobbies SET next_event_sequence=next_event_sequence+1 WHERE id=$1 RETURNING next_event_sequence-1 AS seq",[lobby])).rows[0].seq;await pool.query("INSERT INTO co_op_world_events(lobby_id,sequence,event_type,actor_player_id,payload) VALUES($1,$2,'position',$3,$4::jsonb)",[lobby,seq,member.player_id,JSON.stringify({x:-2350,y:1370})]);}const codes=await Promise.all([worker(0,app.server.address().port),worker(1,app.server.address().port)]);assert.deepEqual(codes,[0,0]);console.log('PASS both actual Godot clients');
 const self=await Promise.all(tokens.map(async t=>(await app.inject({method:'GET',url:'/v1/social/profile',headers:{authorization:'Bearer '+t}})).json()));
 const inspect=(t,id)=>app.inject({method:'GET',url:'/v1/social/friend-profile?playerId='+id,headers:t?{authorization:'Bearer '+t}:{}});
 assert.equal((await inspect(null,self[1].id)).statusCode,401);
 assert.equal((await inspect(tokens[0],'invalid')).statusCode,400);
 assert.equal((await inspect(tokens[0],self[1].id)).statusCode,404);
 const ranking=(t,category)=>app.inject({method:'GET',url:'/v1/social/leaderboard?category='+category,headers:t?{authorization:'Bearer '+t}:{}});
 assert.equal((await ranking(null,'combat')).statusCode,401);
 assert.equal((await ranking(tokens[0],'gold')).statusCode,400);
 assert.equal((await ranking(tokens[0],'combat')).json().rows.length,1);

 await call('/v1/social/friends',{playerId:self[1].id,action:'request'},tokens[0]);
 const pending=(await app.inject({method:'GET',url:'/v1/social/friends',headers:{authorization:'Bearer '+tokens[1]}})).json().friends;
 assert.deepEqual(pending[0].badges,[]);
 assert.equal((await ranking(tokens[1],'achievements')).json().rows.length,1);
 assert.equal((await inspect(tokens[1],self[0].id)).statusCode,404);
 await call('/v1/social/friends',{playerId:self[0].id,action:'accept'},tokens[1]);
 for(const t of tokens){
  const friends=(await app.inject({method:'GET',url:'/v1/social/friends',headers:{authorization:'Bearer '+t}})).json().friends;
  assert.equal(friends.length,1);assert.equal(friends[0].title,'Dawn Wanderer');assert.deepEqual(friends[0].badges,['Dawn Wanderer']);
 }
 for(const [category,score] of [['achievements',1],['exploration',0],['combat',1]]){
  const response=await ranking(tokens[0],category);assert.equal(response.statusCode,200);
  const board=response.json();assert.equal(board.scope,'friends');assert.equal(board.rows.length,2);
  assert.ok(board.rows.every(r=>r.rank===1&&r.score===score));
  assert.equal(board.rows.filter(r=>r.self).length,1);
 }
 // Seed a distinct landmark only for a disposable QA account to test unequal rank.
 await pool.query("INSERT INTO online_achievement_exploration(player_id,region_id,objective_id) VALUES($1,'six_zone_willow_fields','willow_bridge')",[self[1].id]);
 const unequal=(await ranking(tokens[0],'exploration')).json().rows;
 assert.deepEqual(unequal.map(r=>[r.id,r.score,r.rank]),[[self[1].id,1,1],[self[0].id,0,2]]);
 await pool.query("DELETE FROM online_achievement_exploration WHERE player_id=$1",[self[1].id]);
 const globalBoard=t=>app.inject({method:'GET',url:'/v1/social/leaderboard?category=combat&scope=global',headers:{authorization:'Bearer '+t}});
 const visibility=(t,enabled)=>app.inject({method:'POST',url:'/v1/social/leaderboard/visibility',headers:{authorization:'Bearer '+t},payload:{enabled}});
 let global=(await globalBoard(tokens[0])).json();
 assert.equal(global.enabled,false);assert.ok(!global.rows.some(r=>r.id===self[0].id||r.id===self[1].id));
 assert.equal((await visibility(tokens[0],true)).statusCode,200);
 global=(await globalBoard(tokens[1])).json();
 assert.equal(global.enabled,false);assert.ok(global.rows.some(r=>r.id===self[0].id));assert.ok(!global.rows.some(r=>r.self));
 assert.equal((await visibility(tokens[1],true)).statusCode,200);
 global=(await globalBoard(tokens[1])).json();
 assert.equal(global.enabled,true);assert.ok(global.rows.some(r=>r.self));
 assert.ok(global.rows.length<=51);
 assert.equal((await visibility(tokens[1],false)).statusCode,200);
 assert.ok(!(await globalBoard(tokens[0])).json().rows.some(r=>r.id===self[1].id));
 await visibility(tokens[0],false);
 console.log('PASS global rankings opt-in, own rank, visibility revocation and bounded response');
 const monthly=category=>app.inject({method:'GET',url:'/v1/social/leaderboard?category='+category+'&period=monthly',headers:{authorization:'Bearer '+tokens[0]}});
 const monthlyScore=async(category,id)=>{const r=await monthly(category);assert.equal(r.statusCode,200);return r.json().rows.find(x=>x.id===id).score;};
 const calendar=(await monthly('combat')).json();
 const now=new Date(calendar.serverTime);
 const start=new Date(Date.UTC(now.getUTCFullYear(),now.getUTCMonth(),1));
 const end=new Date(Date.UTC(now.getUTCFullYear(),now.getUTCMonth()+1,1));
 assert.equal(calendar.season,start.toISOString().slice(0,7));assert.equal(calendar.resetAt,end.getTime());
 for(const category of ['achievements','combat'])assert.equal(await monthlyScore(category,self[1].id),1);
 assert.equal(await monthlyScore('exploration',self[1].id),0);
 // Historical and future rows are isolated QA fixtures only.
 await pool.query("INSERT INTO online_season_exploration(player_id,season_start,region_id,objective_id) VALUES($1,$2::date,'six_zone_willow_fields','willow_bridge'),($1,($2::date-interval '1 month')::date,'six_zone_willow_fields','willow_ruins'),($1,($2::date+interval '1 month')::date,'six_zone_willow_fields','willow_ruins')",[self[1].id,start.toISOString().slice(0,10)]);
 assert.equal(await monthlyScore('exploration',self[1].id),1);
 assert.equal((await ranking(tokens[0],'exploration')).json().rows.find(r=>r.id===self[1].id).score,0);
 await pool.query("DELETE FROM online_season_exploration WHERE player_id=$1",[self[1].id]);
 const ledger=(await pool.query("SELECT id,created_at FROM currency_ledger WHERE player_id=$1 AND reason IN ('coop_monster_defeat','online_achievement') AND currency_id='gold'",[self[1].id])).rows;
 try{
  for(const entry of ledger)await pool.query("UPDATE currency_ledger SET created_at=$2 WHERE id=$1",[entry.id,new Date(start.getTime()-1)]);
  for(const category of ['combat','achievements']){assert.equal(await monthlyScore(category,self[1].id),0);assert.equal((await ranking(tokens[0],category)).json().rows.find(r=>r.id===self[1].id).score,1);}
  for(const entry of ledger)await pool.query("UPDATE currency_ledger SET created_at=$2 WHERE id=$1",[entry.id,end]);
  for(const category of ['combat','achievements'])assert.equal(await monthlyScore(category,self[1].id),0);
  for(const entry of ledger)await pool.query("UPDATE currency_ledger SET created_at=$2 WHERE id=$1",[entry.id,start]);
  for(const category of ['combat','achievements'])assert.equal(await monthlyScore(category,self[1].id),1);
 }finally{for(const entry of ledger)await pool.query("UPDATE currency_ledger SET created_at=$2 WHERE id=$1",[entry.id,entry.created_at]);}
 console.log('PASS seasonal UTC boundaries, lifetime isolation and current-month exploration');
 const inspected=await inspect(tokens[0],self[1].id);
 assert.equal(inspected.statusCode,200);
 assert.equal(inspected.headers['cache-control'],'no-store');
 const inspectedBody=inspected.json();
 assert.equal(inspectedBody.name,self[1].name);
 assert.equal(inspectedBody.title,'Dawn Wanderer');
 assert.equal(inspectedBody.achievementCount,1);
 assert.equal(inspectedBody.stats.victories,1);
 assert.deepEqual(inspectedBody.badges.map(b=>b.name),['Dawn Wanderer']);
 assert.deepEqual(Object.keys(inspectedBody).sort(),['achievementCount','achievementTotal','avatar','badges','id','name','online','stats','title'].sort());
 assert.equal((await inspect(tokens[0],self[0].id)).statusCode,404);
 // Revoke the relationship and verify access immediately, then restore the QA friendship.
 await call('/v1/social/friends',{playerId:self[1].id,action:'remove'},tokens[0]);
 assert.equal((await inspect(tokens[0],self[1].id)).statusCode,404);
 await call('/v1/social/friends',{playerId:self[1].id,action:'request'},tokens[0]);
 await call('/v1/social/friends',{playerId:self[0].id,action:'accept'},tokens[1]);
 await pool.query("INSERT INTO blocks(player_id,blocked_id) VALUES($1,$2) ON CONFLICT DO NOTHING",[self[1].id,self[0].id]);
 assert.equal((await ranking(tokens[0],'combat')).json().rows.length,1);
 assert.equal((await ranking(tokens[1],'combat')).json().rows.length,1);
 assert.equal((await inspect(tokens[0],self[1].id)).statusCode,404);
 assert.equal((await inspect(tokens[1],self[0].id)).statusCode,404);
 await pool.query("DELETE FROM blocks WHERE player_id=$1 AND blocked_id=$2",[self[1].id,self[0].id]);
 console.log('PASS friend profile private field exclusion, accepted-only permission, removal and blocking');
 console.log('PASS accepted friend title visibility');
 const snapshot=await new Promise((resolve,reject)=>{
  const ws=new WebSocket('ws://127.0.0.1:'+app.server.address().port+'/v1/realtime?lobbyId='+lobby,{headers:{authorization:'Bearer '+tokens[0]}});
  const timer=setTimeout(()=>{ws.terminate();reject(Error('title snapshot timeout'));},7000);
  ws.on('error',e=>{clearTimeout(timer);reject(e);});
  ws.on('message',raw=>{const m=JSON.parse(String(raw));if(m.type==='snapshot'){clearTimeout(timer);ws.close();resolve(m);}});
 });
 assert.equal(snapshot.members.length,2);
 assert.ok(snapshot.members.every(m=>m.title==='Dawn Wanderer'));
 console.log('PASS equipped titles on authoritative expedition reconnect snapshot');
 const live=new WebSocket('ws://127.0.0.1:'+app.server.address().port+'/v1/realtime?lobbyId='+lobby,{headers:{authorization:'Bearer '+tokens[0]}});
 const waitMessage=(kind)=>new Promise((resolve,reject)=>{
  const timer=setTimeout(()=>{live.off('message',handler);reject(Error('live '+kind+' timeout'));},7000);
  const handler=raw=>{const m=JSON.parse(String(raw));if(m.type===kind){clearTimeout(timer);live.off('message',handler);resolve(m);}};
  live.on('message',handler);
 });
 try{
  await waitMessage('snapshot');
  await call('/v1/social/title',{titleId:''},tokens[1]);
  let refresh=waitMessage('player_titles');live.send(JSON.stringify({type:'ping'}));
  assert.equal((await refresh).players.find(x=>x.playerId===self[1].id).title,'');
  await call('/v1/social/title',{titleId:'first_duty'},tokens[1]);
  refresh=waitMessage('player_titles');live.send(JSON.stringify({type:'ping'}));
  assert.equal((await refresh).players.find(x=>x.playerId===self[1].id).title,'Dawn Wanderer');
  console.log('PASS live expedition unequip and re-equip without reconnect');
 }finally{live.close();}



 const get=async(t)=>app.inject({method:'GET',url:'/v1/daily-quests',headers:t?{authorization:'Bearer '+t}:{}});
 const claim=async(t,id,date,extra={})=>app.inject({method:'POST',url:'/v1/daily-quests/claim',headers:{authorization:'Bearer '+t},payload:{id,date,...extra}});
 assert.equal((await get(null)).statusCode,401);
 for(const token of tokens){
  let r=(await get(token)).json();
  assert.equal(r.rows[1].progress,1);assert.equal(r.rows[2].progress,1);
  const credit=(await pool.query("SELECT encounter_credits FROM online_daily_quests WHERE player_id=$1 AND quest_day=$2",[r.playerId,r.date])).rows[0];
  assert.deepEqual(credit.encounter_credits,['willow']);

  assert.ok(r.rows[0].claimed&&r.rows[2].claimed&&r.rows[4].claimed);
  assert.equal(r.rows[5].can_claim,false);
  assert.equal((await claim(token,'activity_3',r.date)).statusCode,409);
  assert.equal((await claim(token,'activity_1',r.date)).statusCode,409);
  assert.equal((await claim(token,'bonus',r.date)).statusCode,409);
  assert.equal((await claim(token,'victories','2000-01-01')).statusCode,409);
  assert.equal((await claim(token,'victories',r.date,{progress:3})).statusCode,400);
  const db=await pool.connect();
  try{await db.query('BEGIN');for(let i=0;i<4;i++)await recordOnlineDailyVictory(db,r.playerId,false);await db.query('COMMIT');}catch(e){await db.query('ROLLBACK');throw e;}finally{db.release();}
  r=(await get(token)).json();assert.equal(r.rows[1].progress,3);
  const batch=(date)=>app.inject({method:'POST',url:'/v1/daily-quests/claim-all',headers:{authorization:'Bearer '+token},payload:{date}});
  assert.equal((await batch('2000-01-01')).statusCode,409);
  const claims=await Promise.all([batch(r.date),batch(r.date)]);
  assert.deepEqual(claims.map(x=>x.statusCode).sort(),[200,409]);
  assert.deepEqual(claims.find(x=>x.statusCode===200).json().awards.map(x=>x.id),['victories','bonus','activity_3']);
  assert.equal((await claim(token,'bonus',r.date)).statusCode,409);
  const wallet=(await app.inject({method:'GET',url:'/v1/auth/wallet',headers:{authorization:'Bearer '+token}})).json();
  assert.equal(Number(wallet.gold),1715);assert.equal(Number(wallet.currencies.crystals),160);
  assert.ok((await get(token)).json().rows.every(x=>x.claimed));
  const weekly=async()=> (await app.inject({method:'GET',url:'/v1/daily-quests/weekly',headers:{authorization:'Bearer '+token}})).json();
  const weeklyClaim=(id,date)=>app.inject({method:'POST',url:'/v1/daily-quests/weekly/claim',headers:{authorization:'Bearer '+token},payload:{id,date}});
  let w=await weekly();
  assert.equal(w.rows[0].progress,1);assert.equal(w.rows[1].progress,3);assert.equal(w.rows[2].progress,1);
  assert.equal(new Date(w.date+'T00:00:00Z').getUTCDay(),1);
  assert.equal(w.resetAt-Date.parse(w.date+'T00:00:00Z'),604800000);
  assert.ok(w.serverTime<w.resetAt);
  assert.equal((await weeklyClaim('bonus',w.date)).statusCode,409);
  assert.equal((await weeklyClaim('shared','2000-01-03')).statusCode,409);
  // Previous-week and future-day fixtures must never contribute.
  await pool.query("INSERT INTO online_daily_quests(player_id,quest_day,victories,shared_victories,claimed) VALUES($1,$2::date-1,3,1,ARRAY['checkin']),($1,(CURRENT_TIMESTAMP AT TIME ZONE 'UTC')::date+1,3,1,ARRAY['checkin']) ON CONFLICT DO NOTHING",[r.playerId,w.date]);
  assert.equal((await weekly()).rows[0].progress,1);
  // Only elapsed days can count; seed isolated test accounts for those days.
  await pool.query("INSERT INTO online_daily_quests(player_id,quest_day,victories,shared_victories,claimed) SELECT $1,d::date,3,1,ARRAY['checkin'] FROM generate_series($2::date, (CURRENT_TIMESTAMP AT TIME ZONE 'UTC')::date-1,interval '1 day') d ON CONFLICT DO NOTHING",[r.playerId,w.date]);
  w=await weekly();
  let payout=0,crystals=0;
  const ready=w.rows.slice(0,3).filter(x=>x.can_claim);
  const batchWeekly=()=>app.inject({method:'POST',url:'/v1/daily-quests/weekly/claim-all',headers:{authorization:'Bearer '+token},payload:{date:w.date}});
  if(ready.length){
   const concurrent=await Promise.all([batchWeekly(),batchWeekly()]);
   assert.deepEqual(concurrent.map(x=>x.statusCode).sort(),[200,409]);
   const awards=concurrent.find(x=>x.statusCode===200).json().awards;
   assert.equal(awards.length,ready.length+(ready.length===3?1:0));
   payout=awards.reduce((sum,x)=>sum+x.gold,0);crystals=awards.reduce((sum,x)=>sum+x.crystals,0);
  }
  assert.equal((await weeklyClaim('bonus',w.date)).statusCode,409);
  const history=(await app.inject({method:'GET',url:'/v1/daily-quests/history',headers:{authorization:'Bearer '+token}})).json();
  assert.equal(history.playerId,r.playerId);
  assert.equal(history.entries.filter(x=>x.period==='Daily').length,4);
  assert.equal(history.entries.filter(x=>x.period==='Activity').length,2);
  assert.equal(history.entries.filter(x=>x.period==='Activity').reduce((a,x)=>a+x.gold,0),300);
  assert.equal(history.entries.reduce((a,x)=>a+x.gold,0),1700+payout);
  assert.equal(history.entries.reduce((a,x)=>a+x.crystals,0),160+crystals);
  const denied=await app.inject({method:'GET',url:'/v1/daily-quests/history'});assert.equal(denied.statusCode,401);
  const finalWallet=(await app.inject({method:'GET',url:'/v1/auth/wallet',headers:{authorization:'Bearer '+token}})).json();
  assert.equal(Number(finalWallet.gold),1715+payout);assert.equal(Number(finalWallet.currencies.crystals),160+crystals);
  console.log('PASS weekly boundaries, period exclusion, claim eligibility, concurrency and exact payout',payout,crystals);
  const monthly=async()=> (await app.inject({method:'GET',url:'/v1/daily-quests/monthly',headers:{authorization:'Bearer '+token}})).json();
  let m=await monthly();
  assert.equal(m.date.slice(-2),'01');
  const start=new Date(m.date+'T00:00:00Z');
  assert.equal(m.resetAt,Date.UTC(start.getUTCFullYear(),start.getUTCMonth()+1,1));
  assert.ok(m.rows.every(x=>!x.claimed));
  const monthlyClaim=(id,date)=>app.inject({method:'POST',url:'/v1/daily-quests/monthly/claim',headers:{authorization:'Bearer '+token},payload:{id,date}});
  assert.equal((await monthlyClaim('bonus',m.date)).statusCode,409);
  assert.equal((await monthlyClaim('checkins','2000-01-01')).statusCode,409);
  const before=m.rows.map(x=>x.progress);
  await pool.query("INSERT INTO online_daily_quests(player_id,quest_day,victories,shared_victories,claimed) VALUES($1,$2::date-1,3,1,ARRAY['checkin']),($1,(CURRENT_TIMESTAMP AT TIME ZONE 'UTC')::date+2,3,1,ARRAY['checkin']) ON CONFLICT DO NOTHING",[r.playerId,m.date]);
  assert.deepEqual((await monthly()).rows.map(x=>x.progress),before);
  await pool.query("INSERT INTO online_daily_quests(player_id,quest_day,victories,shared_victories,claimed) SELECT $1,d::date,3,1,ARRAY['checkin'] FROM generate_series($2::date,(CURRENT_TIMESTAMP AT TIME ZONE 'UTC')::date-1,interval '1 day') d ON CONFLICT DO NOTHING",[r.playerId,m.date]);
  m=await monthly();
  const available=m.rows.slice(0,3).filter(x=>x.can_claim);
  const monthlyBatch=()=>app.inject({method:'POST',url:'/v1/daily-quests/monthly/claim-all',headers:{authorization:'Bearer '+token},payload:{date:m.date}});
  let mg=0,mc=0;
  if(available.length){
   const batch=await Promise.all([monthlyBatch(),monthlyBatch()]);
   assert.deepEqual(batch.map(x=>x.statusCode).sort(),[200,409]);
   const awards=batch.find(x=>x.statusCode===200).json().awards;
   assert.equal(awards.length,available.length+(available.length===3?1:0));
   mg=awards.reduce((a,x)=>a+x.gold,0);mc=awards.reduce((a,x)=>a+x.crystals,0);
  }
  assert.equal((await monthlyBatch()).statusCode,409);
  const monthlyHistory=(await app.inject({method:'GET',url:'/v1/daily-quests/history',headers:{authorization:'Bearer '+token}})).json().entries.filter(x=>x.period==='Monthly');
  assert.equal(monthlyHistory.reduce((a,x)=>a+x.gold,0),mg);
  assert.equal(monthlyHistory.reduce((a,x)=>a+x.crystals,0),mc);
  const mwallet=(await app.inject({method:'GET',url:'/v1/auth/wallet',headers:{authorization:'Bearer '+token}})).json();
  assert.equal(Number(mwallet.gold),1715+payout+mg);
  assert.equal(Number(mwallet.currencies.crystals),160+crystals+mc);
  console.log('PASS monthly boundaries, excluded future days, independent claims, concurrency, bonus and ledger payout',mg,mc);
  const ach=async()=> (await app.inject({method:'GET',url:'/v1/daily-quests/achievements',headers:{authorization:'Bearer '+token}})).json();
  const achClaim=id=>app.inject({method:'POST',url:'/v1/daily-quests/achievements/claim',headers:{authorization:'Bearer '+token},payload:{id}});
  const achBatch=()=>app.inject({method:'POST',url:'/v1/daily-quests/achievements/claim-all',headers:{authorization:'Bearer '+token},payload:{}});
  let a=await ach();
  assert.equal(a.rows[0].claimed,true);
  assert.equal(a.rows[1].progress,1); // seeded daily credits are not lifetime combat payouts
  assert.equal((await achClaim('first_duty')).statusCode,409);
  assert.equal((await achClaim('cassien')).statusCode,409);
  if(mg===14000){
   assert.equal(a.rows[5].can_claim,true);
   const batch=await Promise.all([achBatch(),achBatch()]);
   assert.deepEqual(batch.map(x=>x.statusCode).sort(),[200,409]);
   assert.equal(batch.find(x=>x.statusCode===200).json().awards[0].id,'month_complete');
   const final=(await app.inject({method:'GET',url:'/v1/auth/wallet',headers:{authorization:'Bearer '+token}})).json();
   assert.equal(Number(final.gold),1715+payout+mg+2000);
   assert.equal(Number(final.currencies.crystals),160+crystals+mc+200);
  }
  assert.equal((await achBatch()).statusCode,409);
  assert.equal((await app.inject({method:'GET',url:'/v1/daily-quests/achievements'})).statusCode,401);
  console.log('PASS lifetime achievements, once-only claims, actual ledger combat count, concurrent claim protection');
  const profile=async()=> (await app.inject({method:'GET',url:'/v1/social/profile',headers:{authorization:'Bearer '+token}})).json();
  const equip=titleId=>app.inject({method:'POST',url:'/v1/social/title',headers:{authorization:'Bearer '+token},payload:{titleId}});
  const p=await profile();
  assert.equal(p.title,'Dawn Wanderer');assert.equal(p.equippedTitle,'first_duty');
  assert.equal(p.titles.find(t=>t.id==='first_duty').unlocked,true);
  assert.equal(p.titles.find(t=>t.id==='cassien').unlocked,false);
  assert.equal((await equip('cassien')).statusCode,403);
  assert.equal((await equip('arbitrary')).statusCode,400);
  const other=tokens.find(t=>t!==token);
  const lookup=(await app.inject({method:'GET',url:'/v1/social/search?name='+encodeURIComponent(p.name),headers:{authorization:'Bearer '+other}})).json();
  assert.equal(lookup.players[0].title,'Dawn Wanderer');
  const changed=await equip('');
  assert.equal(changed.statusCode,200);assert.equal((await profile()).title,'');
  assert.equal((await equip('first_duty')).statusCode,200);
  assert.equal((await profile()).title,'Dawn Wanderer');
  console.log('PASS earned titles, locked title rejection, public lookup, unequip and re-equip');




 }
 console.log('PASS real contributor progress; invalid request, stale date, premature bonus, capped progress, concurrent claims and exact server wallet payout');}catch(e){console.error('FAIL',e.message);process.exitCode=1;}finally{if(lobby){for(const t of tokens.slice().reverse()){try{await call(`/v1/co-op/lobbies/${lobby}/leave`,{},t);}catch{}}}await app.close();if(lobby)await pool.query('DELETE FROM co_op_lobbies WHERE id=$1',[lobby]);await pool.query('DELETE FROM accounts WHERE email = ANY($1)',[emails]);await pool.end();console.log('Test fixtures cleaned');}