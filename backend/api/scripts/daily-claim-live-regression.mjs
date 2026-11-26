import assert from 'node:assert/strict';
import {randomBytes} from 'node:crypto';
import {config} from '../src/config.ts';
import {pool} from '../src/db.ts';
assert.ok(['localhost','127.0.0.1','[::1]'].includes(new URL(config.DATABASE_URL).hostname));
const base='http://127.0.0.1:8787';
const name='QaPeriod'+randomBytes(5).toString('hex'),email=name.toLowerCase()+'@example.test',password=randomBytes(16).toString('hex');
let token='',id='';
async function request(method,path,payload){const r=await fetch(base+path,{method,headers:{...(token?{authorization:'Bearer '+token}:{}),...(payload?{'content-type':'application/json'}:{})},...(payload?{body:JSON.stringify(payload)}:{})});return {status:r.status,data:await r.json()};}
async function read(path){const r=await request('GET',path);assert.equal(r.status,200,JSON.stringify(r.data));return r.data;}
const quest='/v1/daily-quests';
const get=path=>read(quest+(path||''));
const wallet=()=>read('/v1/auth/wallet');
const claim=(path,key,date)=>request('POST',quest+path+'/claim',{id:key,date});
const all=(path,date)=>request('POST',quest+path+'/claim-all',{date});
try{
 assert.equal((await read('/health')).database,'ok');
 assert.equal((await request('POST','/v1/auth/register',{email,playerName:name,password})).status,201);
 const login=await request('POST','/v1/auth/login',{playerName:name,password});assert.equal(login.status,200);token=login.data.accessToken;
 const initial=await wallet(),daily=await get('');id=daily.playerId;const date=daily.date;
 const checkin=await Promise.all(Array.from({length:4},()=>claim('','checkin',date)));
 assert.deepEqual(checkin.map(x=>x.status).sort(),[200,409,409,409]);
 assert.ok(checkin.every(x=>x.data.rows.find(r=>r.id==='checkin').claimed));
 assert.equal(Number((await wallet()).gold)-Number(initial.gold),150);
 console.log('LIVE API: one daily payout, duplicate requests return claimed state');
 const week=await get('/weekly'),month=await get('/monthly');
 assert.equal(week.rows[0].progress,1);assert.equal(month.rows[0].progress,1);
 // Fixture only: simulate earned progress on elapsed days. Do not change the clock or real accounts.
 await pool.query("INSERT INTO online_daily_quests(player_id,quest_day,victories,shared_victories,claimed) SELECT $1,d::date,3,1,ARRAY['checkin'] FROM generate_series($2::date,$3::date-1,interval '1 day') d ON CONFLICT DO NOTHING",[id,month.date,date]);
 await pool.query("UPDATE online_daily_quests SET victories=3,shared_victories=1 WHERE player_id=$1 AND quest_day=$2",[id,date]);
 // Future progress must not contribute, even if present in storage.
 await pool.query("INSERT INTO online_daily_quests(player_id,quest_day,victories,shared_victories,claimed) VALUES($1,$2::date+1,3,1,ARRAY['checkin']) ON CONFLICT DO NOTHING",[id,date]);
 let awardsGold=150,awardsCrystals=0;
 for(const [path,period,table,column] of [['/weekly',week,'online_weekly_quests','week_start'],['/monthly',month,'online_monthly_quests','month_start']]){
  const elapsed=1+Math.round((Date.parse(date)-Date.parse(period.date))/86400000);let status=await get(path);
  assert.equal(status.rows[0].progress,Math.min(status.rows[0].target,elapsed));
  assert.equal(status.rows[1].progress,Math.min(status.rows[1].target,elapsed*3));
  assert.equal(status.rows[2].progress,Math.min(status.rows[2].target,elapsed));
  assert.ok(status.resetAt>status.serverTime);assert.equal(new Date(status.resetAt).getUTCHours(),0);
  if(path==='/weekly')assert.equal(new Date(status.resetAt).getUTCDay(),1);else assert.equal(new Date(status.resetAt).getUTCDate(),1);
  const ready=status.rows.filter(x=>x.can_claim);
  const expired=await all(path,'2000-01-01');assert.equal(expired.status,409);assert.equal(expired.data.date,period.date);
  if(ready.length){
   const race=await Promise.all([all(path,period.date),all(path,period.date),all(path,period.date)]);
   assert.deepEqual(race.map(x=>x.status).sort(),[200,409,409]);
   const paid=race.find(x=>x.status===200).data.awards;assert.equal(paid.length,ready.length+(ready.length===3?1:0));
   awardsGold+=paid.reduce((n,x)=>n+x.gold,0);awardsCrystals+=paid.reduce((n,x)=>n+x.crystals,0);
   await pool.query(`UPDATE ${table} SET claimed='{}' WHERE player_id=$1 AND ${column}=$2`,[id,period.date]);
   status=await get(path);for(const x of paid)assert.ok(status.rows.find(r=>r.id===x.id).claimed);
   assert.equal((await all(path,period.date)).status,409);
   console.log('LIVE API:',path,'concurrent claim, recovered marker, stale period and future day exclusion PASS',paid.length,'awards');
  }else console.log('LIVE API:',path,'future day exclusion and period boundaries PASS; no eligible task yet');
 }
 const final=await wallet();assert.equal(Number(final.gold)-Number(initial.gold),awardsGold);assert.equal(Number(final.currencies.crystals)-Number(initial.currencies.crystals),awardsCrystals);
 const ledger=await pool.query("SELECT reason,ref_id,currency_id,count(*)::int AS n FROM currency_ledger WHERE player_id=$1 AND reason IN ('online_daily_quest','online_weekly_quest','online_monthly_quest') GROUP BY reason,ref_id,currency_id",[id]);assert.ok(ledger.rows.every(x=>x.n===1));
 console.log('LIVE API PASS: exact wallet totals, no duplicate ledger entries');
}finally{await pool.query('DELETE FROM accounts WHERE email=$1',[email]);await pool.end();console.log('Isolated live test account removed');}
