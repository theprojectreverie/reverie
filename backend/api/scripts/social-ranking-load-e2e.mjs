import Fastify from 'fastify';
import jwt from '@fastify/jwt';
import assert from 'node:assert/strict';
import {randomBytes} from 'node:crypto';
import {performance} from 'node:perf_hooks';
import {config} from '../src/config.ts';
import {pool} from '../src/db.ts';
import {socialRoutes} from '../src/routes/social.ts';
assert.ok(['localhost','127.0.0.1','[::1]'].includes(new URL(config.DATABASE_URL).hostname));
const N=Number(process.env.QA_CLIENTS??48),rounds=6,suffix=randomBytes(5).toString('hex'),emails=[],players=[];
assert.ok(Number.isInteger(N)&&N>=4&&N<=120);
const app=Fastify({logger:false});
const times={summary:[],ranking:[]};
let maxWaiting=0;
const stats=values=>{values.sort((a,b)=>a-b);return {requests:values.length,p50:Math.round(values[Math.ceil(values.length*.5)-1]*10)/10,p95:Math.round(values[Math.ceil(values.length*.95)-1]*10)/10,p99:Math.round(values[Math.ceil(values.length*.99)-1]*10)/10};};
try{
 await app.register(jwt,{secret:config.JWT_SECRET});await app.register(socialRoutes,{prefix:'/v1/social'});await app.ready();
 for(let i=0;i<N;i++){
  const email='rank-load-'+suffix+'-'+i+'@example.test';emails.push(email);
  const account=(await pool.query("INSERT INTO accounts(email,password_hash,email_verified) VALUES($1,'disposable-test-no-login',true) RETURNING id,token_version",[email])).rows[0];
  const p=(await pool.query("INSERT INTO players(account_id,name,settings) VALUES($1,$2,jsonb_build_object('global_rankings',true)) RETURNING id",[account.id,'Rank'+suffix+i])).rows[0];
  const score=10+i;
  await pool.query("INSERT INTO currency_ledger(player_id,currency_id,delta,balance_after,reason,ref_type,ref_id,idempotency_key) SELECT $1,'gold',15,15,'coop_monster_defeat','monster','qa','rank-load:'||n FROM generate_series(1,$2::int) n",[p.id,score]);
  players.push({id:p.id,score,token:app.jwt.sign({sub:account.id,playerId:p.id,tokenVersion:account.token_version})});
 }
 const base=await app.listen({host:'127.0.0.1',port:0});
 const check=async(p,kind)=>{
  const path=kind==='summary'?'/summary':'/leaderboard?category=combat&scope=global&period=monthly';
  const start=performance.now();
  const response=await fetch(base+'/v1/social'+path,{headers:{authorization:'Bearer '+p.token},signal:AbortSignal.timeout(15000)});
  const body=await response.json();times[kind].push(performance.now()-start);maxWaiting=Math.max(maxWaiting,pool.waitingCount);
  assert.equal(response.status,200);assert.equal(body.playerId,p.id);
  if(kind==='ranking'){const me=body.rows.find(r=>r.self);assert.equal(me.id,p.id);assert.equal(me.score,p.score);assert.ok(body.rows.length<=51);}
  else{assert.equal(body.seasonChallengeClaimable,p.score>=25?2:1);assert.equal(body.seasonClaimable,0);}
 };
 for(let round=0;round<rounds;round++)await Promise.all(players.flatMap(p=>[check(p,'summary'),check(p,'ranking')]));
 console.log(JSON.stringify({clients:N,summary:stats(times.summary),ranking:stats(times.ranking),observedPoolWaiting:maxWaiting,poolWaitingAfter:pool.waitingCount}));
 assert.equal(pool.waitingCount,0);
 console.log('PASS concurrent loopback HTTP ranking and summary reads, account isolation, exact scores and bounded result size');
}finally{await app.close();await pool.query('DELETE FROM accounts WHERE email=ANY($1)',[emails]);assert.equal((await pool.query('SELECT count(*)::int AS n FROM accounts WHERE email=ANY($1)',[emails])).rows[0].n,0);await pool.end();console.log('PASS disposable accounts cleaned up');}
