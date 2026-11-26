import Fastify from 'fastify';
import jwt from '@fastify/jwt';
import {randomBytes} from 'node:crypto';
import assert from 'node:assert/strict';
import {config} from '../src/config.ts';
import {pool} from '../src/db.ts';
import {authRoutes} from '../src/routes/auth.ts';
import {dailyQuestRoutes,recordOnlineDailyVictory} from '../src/routes/daily-quests.ts';
assert.ok(['localhost','127.0.0.1','[::1]'].includes(new URL(config.DATABASE_URL).hostname));
const app=Fastify({logger:false});const suffix=randomBytes(6).toString('hex');const name='QaDaily'+suffix;const email=name.toLowerCase()+'@example.test';const password=randomBytes(16).toString('hex');let token='',id='';
async function request(method,url,payload){return app.inject({method,url,payload,headers:token?{authorization:'Bearer '+token}:{}});}
async function get(path=''){const r=await request('GET','/v1/daily-quests'+path);assert.equal(r.statusCode,200,r.body);return r.json();}
const claim=(key,date,path='')=>request('POST','/v1/daily-quests'+path+'/claim',{id:key,date});
const all=(date,path='')=>request('POST','/v1/daily-quests'+path+'/claim-all',{date});
async function wallet(){const r=await request('GET','/v1/auth/wallet');assert.equal(r.statusCode,200,r.body);return r.json();}
try{
 await app.register(jwt,{secret:config.JWT_SECRET});await app.register(authRoutes,{prefix:'/v1/auth'});await app.register(dailyQuestRoutes,{prefix:'/v1/daily-quests'});
 assert.equal((await request('POST','/v1/auth/register',{email,playerName:name,password})).statusCode,201);
 let login=await request('POST','/v1/auth/login',{playerName:name,password});assert.equal(login.statusCode,200);token=login.json().accessToken;
 let q=await get();id=q.playerId;const day=q.date;const before=await wallet();
 const attempts=await Promise.all(Array.from({length:8},()=>claim('checkin',day)));
 assert.equal(attempts.filter(x=>x.statusCode===200).length,1);assert.equal(attempts.filter(x=>x.statusCode===409).length,7);
 for(const r of attempts)assert.ok(r.json().rows.find(x=>x.id==='checkin').claimed);
 assert.equal(Number((await wallet()).gold)-Number(before.gold),150);assert.ok((await get()).rows.find(x=>x.id==='checkin').claimed);
 console.log('PASS 8 concurrent check-in requests: exactly one 150-gold payout');
 // Re-login and force a lost progress marker on the disposable fixture only.
 token='';login=await request('POST','/v1/auth/login',{playerName:name,password});assert.equal(login.statusCode,200);token=login.json().accessToken;
 await pool.query("UPDATE online_daily_quests SET claimed='{}' WHERE player_id=$1 AND quest_day=$2",[id,day]);
 q=await get();assert.ok(q.rows.find(x=>x.id==='checkin').claimed);assert.equal(q.rows.find(x=>x.id==='checkin').can_claim,false);
 const duplicate=await claim('checkin',day);assert.equal(duplicate.statusCode,409);assert.ok(duplicate.json().rows.find(x=>x.id==='checkin').claimed);
 assert.equal(Number((await wallet()).gold)-Number(before.gold),150);
 console.log('PASS re-login and missing claim marker recover from durable ledger');
 const stale=await claim('checkin','2000-01-01');assert.equal(stale.statusCode,409);assert.equal(stale.json().date,day);
 const db=await pool.connect();try{await db.query('BEGIN');for(let i=0;i<3;i++)await recordOnlineDailyVictory(db,id,true);await db.query('COMMIT');}catch(e){await db.query('ROLLBACK');throw e;}finally{db.release();}
 const batch=await Promise.all([all(day),all(day)]);assert.deepEqual(batch.map(x=>x.statusCode).sort(),[200,409]);
 assert.ok((await get()).rows.every(x=>x.claimed));assert.equal(Number((await wallet()).gold)-Number(before.gold),1500);
 assert.equal(Number((await wallet()).currencies.crystals)-Number(before.currencies.crystals),140);
 const ledger=await pool.query("SELECT ref_id,currency_id,count(*)::int AS n FROM currency_ledger WHERE player_id=$1 AND reason IN ('online_daily_quest','online_activity_quest') GROUP BY ref_id,currency_id",[id]);assert.ok(ledger.rows.every(x=>x.n===1));
 console.log('PASS claim-all, bonuses, stale-date rejection, exact gold and crystal totals');
 const w=await get('/weekly');assert.equal(w.rows[0].progress,1);console.log('PASS weekly check-in counted once');
}finally{await app.close();await pool.query('DELETE FROM accounts WHERE email=$1',[email]);await pool.end();console.log('Isolated test account cleaned');}
