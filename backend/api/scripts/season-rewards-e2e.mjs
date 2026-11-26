import Fastify from 'fastify';
import jwt from '@fastify/jwt';
import assert from 'node:assert/strict';
import {randomBytes} from 'node:crypto';
import {config} from '../src/config.ts';
import {pool} from '../src/db.ts';
import {authRoutes} from '../src/routes/auth.ts';
import {socialRoutes} from '../src/routes/social.ts';
import {playerTitles,dailyQuestRoutes} from '../src/routes/daily-quests.ts';
import {freezeSeason,finalizeDueSeasons,startSeasonFinalizer} from '../src/world/season-rewards.ts';
assert.ok(['localhost','127.0.0.1','[::1]'].includes(new URL(config.DATABASE_URL).hostname));
const season='2001-01-01',suffix=randomBytes(5).toString('hex'),emails=Array.from({length:5},(_,i)=>'season'+i+suffix+'@example.test'),names=emails.map((_,i)=>'Season'+i+suffix);
const app=Fastify({logger:false}),ids=[],tokens=[];
let ownsFixture=false;
const request=(method,url,t,payload)=>app.inject({method,url,headers:t?{authorization:'Bearer '+t}:{},...(payload?{payload}:{})});
try{
 assert.equal((await pool.query('SELECT 1 FROM online_season_finalizations WHERE season_start=$1',[season])).rowCount,0);
 await app.register(jwt,{secret:config.JWT_SECRET});await app.register(authRoutes,{prefix:'/v1/auth'});await app.register(socialRoutes,{prefix:'/v1/social'});await app.register(dailyQuestRoutes,{prefix:'/v1/daily-quests'});await app.ready();
 for(let i=0;i<5;i++){
  const password=randomBytes(16).toString('hex');
  assert.equal((await request('POST','/v1/auth/register',null,{email:emails[i],playerName:names[i],password})).statusCode,201);
  const login=(await request('POST','/v1/auth/login',null,{playerName:names[i],password})).json();tokens.push(login.accessToken);
  ids.push((await request('GET','/v1/social/profile',tokens[i])).json().id);
 }
 for(let i=0;i<5;i++){
  await pool.query("INSERT INTO online_ranking_visibility_events(player_id,enabled,changed_at) VALUES($1,true,'2001-01-15T00:00:00Z')",[ids[i]]);
  if(i===3)await pool.query("INSERT INTO online_ranking_visibility_events(player_id,enabled,changed_at) VALUES($1,false,'2001-01-31T23:59:59Z')",[ids[i]]);
  for(let k=0;k<[2,2,1,5,0][i];k++)await pool.query("INSERT INTO currency_ledger(player_id,currency_id,delta,balance_after,reason,ref_type,ref_id,idempotency_key,created_at) VALUES($1,'gold',15,15,'coop_monster_defeat','monster','qa',$2,'2001-01-20T00:00:00Z')",[ids[i],"season-fixture:"+k]);
 }
 // A later opt-out must not retroactively change the cutoff population.
 await pool.query("INSERT INTO online_ranking_visibility_events(player_id,enabled,changed_at) VALUES($1,false,'2001-02-01T00:00:00Z')",[ids[0]]);
 const db=await pool.connect();try{
  await db.query('BEGIN');
  await assert.rejects(freezeSeason(db,season,playerTitles.map(t=>t.id)),/invalid_reward_season/);
  assert.equal(await freezeSeason(db,'2099-01-01',playerTitles.map(t=>t.id)),false);
  assert.equal(await freezeSeason(db,season,playerTitles.map(t=>t.id),season),true);
  assert.equal(await freezeSeason(db,season,playerTitles.map(t=>t.id),season),false);
  await db.query('COMMIT');ownsFixture=true;
 }catch(e){await db.query('ROLLBACK');throw e;}finally{db.release();}
 const frozen=(await pool.query("SELECT player_id,rank,gold,score FROM online_season_results WHERE season_start=$1 AND category='combat' ORDER BY rank,player_id",[season])).rows;
 assert.equal(frozen.length,3);assert.equal(frozen.find(r=>r.player_id===ids[0]).rank,1);assert.equal(frozen.find(r=>r.player_id===ids[1]).rank,1);assert.equal(frozen.find(r=>r.player_id===ids[2]).rank,3);
 assert.equal(frozen.find(r=>r.player_id===ids[2]).gold,300);
 const hall=(t,category='combat',page=0)=>request('GET','/v1/social/championship-hall?season='+season+'&category='+category+'&page='+page,t);
 const visibility=(t,enabled)=>request('POST','/v1/social/leaderboard/visibility',t,{enabled});
 assert.equal((await hall(null)).statusCode,401);
 assert.equal((await hall(tokens[2],'wallet')).statusCode,400);
 assert.equal((await hall(tokens[2],'combat',-1)).statusCode,400);
 assert.equal((await request('GET','/v1/social/championship-hall?season=2099-01-01',tokens[2])).statusCode,404);
 assert.equal((await hall(tokens[2])).json().rows.length,0);
 for(const t of tokens)assert.equal((await visibility(t,true)).statusCode,200);
 let board=(await hall(tokens[2])).json();
 assert.ok(board.seasons.includes(season));assert.equal(board.season,season);assert.equal(board.rows.length,2);
 assert.deepEqual(board.rows.map(r=>r.id).sort(),ids.slice(0,2).sort());
 assert.ok(board.rows.every(r=>r.rank===1&&r.score===2&&r.title==='Arena Sovereign'));
 assert.equal(board.hasMore,false);
 assert.equal((await hall(tokens[2],'exploration')).json().rows.length,0);
 assert.equal((await hall(tokens[2],'combat',1)).json().rows.length,0);
 // Changing current scores cannot change a frozen winner.
 await pool.query("UPDATE currency_ledger SET created_at='2001-02-01T00:00:00Z' WHERE player_id=$1 AND reason='coop_monster_defeat'",[ids[0]]);
 assert.equal((await hall(tokens[2])).json().rows.find(r=>r.id===ids[0]).score,2);
 await pool.query("INSERT INTO blocks(player_id,blocked_id) VALUES($1,$2)",[ids[0],ids[2]]);
 assert.deepEqual((await hall(tokens[2])).json().rows.map(r=>r.id),[ids[1]]);
 await pool.query("DELETE FROM blocks WHERE player_id=$1 AND blocked_id=$2",[ids[0],ids[2]]);
 await visibility(tokens[1],false);
 assert.deepEqual((await hall(tokens[2])).json().rows.map(r=>r.id),[ids[0]]);
 assert.equal((await hall(tokens[1])).json().rows.some(r=>r.self),false);
 await visibility(tokens[1],true);
 console.log('PASS championship hall frozen scores, tied winners, category and page filters, current consent and block privacy');
 const claim=t=>request('POST','/v1/social/season-results/claim',t,{season,category:'combat'});
 assert.equal((await claim(tokens[3])).statusCode,409);assert.equal((await claim(tokens[4])).statusCode,409);
 assert.equal((await request('POST','/v1/social/title',tokens[0],{titleId:'season_combat_champion'})).statusCode,403);
 const summaryBefore=(await request('GET','/v1/social/summary',tokens[0])).json();
 assert.equal(summaryBefore.seasonClaimable,1);
 assert.deepEqual(summaryBefore.seasonReady,[{id:season+':combat',season,category:'combat'}]);
 const otherSummary=(await request('GET','/v1/social/summary',tokens[3])).json();
 assert.equal(otherSummary.seasonClaimable,0);
 const before=Number((await request('GET','/v1/auth/wallet',tokens[0])).json().gold);
 const claims=await Promise.all([claim(tokens[0]),claim(tokens[0])]);assert.deepEqual(claims.map(r=>r.statusCode).sort(),[200,409]);
 assert.equal(Number((await request('GET','/v1/auth/wallet',tokens[0])).json().gold)-before,1000);
 assert.equal((await request('POST','/v1/social/title',tokens[0],{titleId:'season_combat_champion'})).json().title,'Arena Sovereign');
 const profile=(await request('GET','/v1/social/profile',tokens[0])).json();assert.equal(profile.titles.length,15);assert.equal(profile.achievementCount,0);assert.equal(profile.seasonTitles.length,1);
 const search=(await request('GET','/v1/social/search?name='+names[0],tokens[1])).json();assert.equal(search.players[0].title,'Arena Sovereign');
 const history=(await request('GET','/v1/social/season-results',tokens[0])).json();assert.equal(history.results[0].claimed,true);
 assert.deepEqual(history.championships,[{season,category:'combat',score:2,title:'Arena Sovereign'}]);
 const summaryAfter=(await request('GET','/v1/social/summary',tokens[0])).json();
 assert.equal(summaryAfter.seasonClaimable,0);assert.deepEqual(summaryAfter.seasonReady,[]);
 console.log('PASS personal reward notifications, claim clearing and championship history');
 // Personal challenges are independent of visibility and frozen prizes.
 const player=ids[4],token=tokens[4];
 await visibility(token,false);
 const challenges=async()=>{const r=await request('GET','/v1/social/season-challenges',token);assert.equal(r.statusCode,200);return r.json();};
 const initial=await challenges(),month=initial.season;
 const claimTask=(id,season=month)=>request('POST','/v1/social/season-challenges/claim',token,{id,season});
 assert.ok(initial.rows.every(r=>r.progress===0&&!r.canClaim));
 assert.equal((await claimTask('season_complete')).statusCode,409);
 assert.equal((await claimTask('combat_10','2001-01-01')).statusCode,409);
 assert.equal((await claimTask('forged')).statusCode,400);
 await pool.query("INSERT INTO currency_ledger(player_id,currency_id,delta,balance_after,reason,ref_type,ref_id,idempotency_key,created_at) SELECT $1,'gold',15,15,'coop_monster_defeat','monster','qa','challenge-fixture:'||n,clock_timestamp()-interval '1 second' FROM generate_series(1,25) n",[player]);
 await pool.query("INSERT INTO currency_ledger(player_id,currency_id,delta,balance_after,reason,ref_type,ref_id,idempotency_key,created_at) VALUES($1,'gold',15,15,'coop_monster_defeat','monster','qa','challenge-old',(($2::date-interval '1 day') AT TIME ZONE 'UTC')),($1,'gold',15,15,'coop_monster_defeat','monster','qa','challenge-future',(($2::date+interval '1 month') AT TIME ZONE 'UTC'))",[player,month]);
 await pool.query("INSERT INTO online_season_exploration(player_id,season_start,region_id,objective_id) VALUES($1,$2,'six_zone_willow_fields','willow_bridge'),($1,$2,'six_zone_willow_fields','willow_ruins'),($1,$2,'six_zone_elderwood_grove','elderwood_memorial'),($1,$2,'six_zone_elderwood_grove','elderwood_pillar'),($1,($2::date-interval '1 month')::date,'six_zone_willow_fields','willow_bridge'),($1,($2::date+interval '1 month')::date,'six_zone_willow_fields','willow_bridge')",[player,month]);
 let active=await challenges();
 assert.deepEqual(active.rows.map(r=>r.progress),[10,25,2,4,0]);
 assert.equal((await request('GET','/v1/social/summary',token)).json().seasonChallengeClaimable,4);
 const beforeChallenge=Number((await request('GET','/v1/auth/wallet',token)).json().gold);
 for(const task of active.rows.slice(0,4)){
  const race=await Promise.all([claimTask(task.id),claimTask(task.id)]);
  assert.deepEqual(race.map(r=>r.statusCode).sort(),[200,409]);
 }
 active=await challenges();assert.equal(active.rows[4].canClaim,true);
 assert.equal((await claimTask('season_complete')).statusCode,200);
 assert.equal((await claimTask('season_complete')).statusCode,409);
 assert.equal(Number((await request('GET','/v1/auth/wallet',token)).json().gold)-beforeChallenge,1300);
 assert.ok((await challenges()).rows.every(r=>r.claimed));
 assert.equal((await request('GET','/v1/social/summary',token)).json().seasonChallengeClaimable,0);
 assert.equal((await request('GET','/v1/social/season-challenges',null)).statusCode,401);
 console.log('PASS personal season challenges, current-period scores, opt-out participation, stale rejection, concurrent claims, bonus and exact wallet');
 // Independent disposable account: batch claim unlocks the completion bonus within the same transaction.
 const batchId=ids[3],batchToken=tokens[3];
 await pool.query("INSERT INTO currency_ledger(player_id,currency_id,delta,balance_after,reason,ref_type,ref_id,idempotency_key,created_at) SELECT $1,'gold',15,15,'coop_monster_defeat','monster','qa','batch-fixture:'||n,clock_timestamp()-interval '1 second' FROM generate_series(1,25) n",[batchId]);
 await pool.query("INSERT INTO online_season_exploration(player_id,season_start,region_id,objective_id) SELECT $1,season_start,region_id,objective_id FROM online_season_exploration WHERE player_id=$2 AND season_start=$3",[batchId,player,month]);
 const batch=()=>request('POST','/v1/social/season-challenges/claim-all',batchToken,{season:month});
 const beforeBatch=Number((await request('GET','/v1/auth/wallet',batchToken)).json().gold);
 const batches=await Promise.all([batch(),batch()]);
 assert.deepEqual(batches.map(r=>r.statusCode).sort(),[200,409]);
 const won=batches.find(r=>r.statusCode===200).json();
 assert.equal(won.goldAwarded,1300);assert.equal(won.awards.length,5);assert.ok(won.rows.every(r=>r.claimed));
 assert.equal(Number((await request('GET','/v1/auth/wallet',batchToken)).json().gold)-beforeBatch,1300);
 const challengeHistory=(await request('GET','/v1/daily-quests/history',batchToken)).json().entries.filter(r=>r.period==='Season challenge');
 assert.equal(challengeHistory.length,5);assert.equal(challengeHistory.reduce((sum,r)=>sum+r.gold,0),1300);
 const prizeHistory=(await request('GET','/v1/daily-quests/history',tokens[0])).json().entries.find(r=>r.period==='Season ranking');
 assert.equal(prizeHistory.gold,1000);
 console.log('PASS atomic Claim All including newly unlocked bonus, race protection and seasonal ledger history');
 // Compare the consolidated query with each original quest endpoint, using nonempty data.
 const checkQuestSummary=async token=>{
  const summary=(await request('GET','/v1/social/summary',token)).json();
  for(const [key,suffix] of [['dailyClaimable','/'],['weeklyClaimable','/weekly'],['monthlyClaimable','/monthly']]){
   const response=await request('GET','/v1/daily-quests'+suffix,token);
   assert.equal(response.statusCode,200);
   assert.equal(summary[key],response.json().rows.filter(r=>r.can_claim).length);
  }
 };
 await checkQuestSummary(batchToken);
 await pool.query("INSERT INTO online_daily_quests(player_id,quest_day,victories,shared_victories,claimed) VALUES($1,(CURRENT_TIMESTAMP AT TIME ZONE 'UTC')::date,3,1,ARRAY['checkin']) ON CONFLICT(player_id,quest_day) DO UPDATE SET victories=3,shared_victories=1,claimed=ARRAY['checkin']",[batchId]);
 await checkQuestSummary(batchToken);
 const getPresence=async()=> (await pool.query("SELECT state,last_heartbeat_at FROM player_presence WHERE player_id=$1",[batchId])).rows[0];
 const recent=await getPresence();
 await request('GET','/v1/social/summary',batchToken);
 assert.equal((await getPresence()).last_heartbeat_at.getTime(),recent.last_heartbeat_at.getTime());
 await pool.query("UPDATE player_presence SET last_heartbeat_at=now()-interval '21 seconds' WHERE player_id=$1",[batchId]);
 await request('GET','/v1/social/summary',batchToken);
 assert.ok((await getPresence()).last_heartbeat_at.getTime()>=recent.last_heartbeat_at.getTime());
 await pool.query("UPDATE player_presence SET state='offline' WHERE player_id=$1",[batchId]);
 await request('GET','/v1/social/summary',batchToken);
 assert.equal((await getPresence()).state,'online');
 console.log('PASS consolidated quest summary parity and presence write throttling with immediate online recovery');




 assert.equal((await request('GET','/v1/social/season-results',null)).statusCode,401);
 console.log('PASS frozen cutoff, ties, opt-out exclusion, zero-score exclusion, no early or retroactive production freeze, once-only wallet and seasonal title');
}finally{await app.close();await pool.query('DELETE FROM accounts WHERE email=ANY($1)',[emails]);if(ownsFixture)await pool.query('DELETE FROM online_season_finalizations WHERE season_start=$1',[season]);await pool.end();}
