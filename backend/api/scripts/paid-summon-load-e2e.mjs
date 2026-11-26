import Fastify from "fastify";
import jwt from "@fastify/jwt";
import assert from "node:assert/strict";
import {randomBytes,randomUUID} from "node:crypto";
import {performance} from "node:perf_hooks";
import {config} from "../src/config.ts";
import {pool} from "../src/db.ts";
import {authRoutes} from "../src/routes/auth.ts";
import {summonRoutes} from "../src/routes/summon.ts";
import {summonAdmission} from "../src/world/summon-admission.ts";
import {banners} from "../src/world/summon.ts";
assert.ok(config.NODE_ENV!=="production"&&["localhost","127.0.0.1","[::1]"].includes(new URL(config.DATABASE_URL).hostname));
const app=Fastify({logger:false}),emails=[],players=[];
const count=24,ids=Object.keys(banners);
const call=(token,method,url,payload)=>app.inject({method,url,headers:token?{authorization:"Bearer "+token}:{},...(payload?{payload}:{})});
const request=(p,bannerId,total)=>({bannerId,count:10,currency:"paid_moonstones",requestId:randomUUID(),expectedPaidTotal:String(total)});
const pull=(p,payload)=>call(p.token,"POST","/v1/summon/pull",payload);
async function success(p,payload){const r=await pull(p,payload);assert.equal(r.statusCode,200,r.body);return r.json();}
async function state(p){const r=await call(p.token,"GET","/v1/summon/state");assert.equal(r.statusCode,200,r.body);return r.json();}
function metrics(values){const s=[...values].sort((a,b)=>a-b);return {p50:Math.round(s[Math.ceil(s.length*.5)-1]),p95:Math.round(s[Math.ceil(s.length*.95)-1]),max:Math.round(s.at(-1))};}
try{
 await app.register(jwt,{secret:config.JWT_SECRET});
 await app.register(authRoutes,{prefix:"/v1/auth"});
 await app.register(summonRoutes,{prefix:"/v1/summon"});
 for(let i=0;i<count;i++){
  const playerName="QaLoad"+randomBytes(5).toString("hex"),email=playerName.toLowerCase()+"@example.test",password=randomBytes(16).toString("hex");
  emails.push(email);
  assert.equal((await call("","POST","/v1/auth/register",{playerName,email,password})).statusCode,201);
  const l=await call("","POST","/v1/auth/login",{playerName,password});assert.equal(l.statusCode,200);
  players.push({id:l.json().player.id,token:l.json().accessToken,banner:ids[i%ids.length]});
 }
 const playerIds=players.map(p=>p.id);
 await pool.query("INSERT INTO player_currencies(player_id,currency_id,balance) SELECT p,'paid_moonstones',12000 FROM unnest($1::uuid[]) AS p ON CONFLICT(player_id,currency_id) DO UPDATE SET balance=EXCLUDED.balance",[playerIds]);
 for(let round=0;round<9;round++){
  await Promise.all(players.map(p=>success(p,request(p,p.banner,round*10))));
 }
 console.log("Prepared 24 accounts with 90 paid pulls each");
 const times=[],start=performance.now();
 let maxActive=0,maxQueued=0;
 const watch=setInterval(()=>{maxActive=Math.max(maxActive,summonAdmission.activeCount);maxQueued=Math.max(maxQueued,summonAdmission.queuedCount);},2);
 try{
  const jobs=players.map(async p=>{const t=performance.now();const payload=request(p,p.banner,90);const result=await success(p,payload);times.push(performance.now()-t);return {p,payload,result};});
  const probes=Promise.all(Array.from({length:4},async()=>{const t=performance.now();await pool.query("SELECT 1");return performance.now()-t;}));
  const [results,probeTimes]=await Promise.all([Promise.all(jobs),probes]);
  const elapsed=performance.now()-start;
  assert.equal(results.length,count);
  for(const {p,result} of results){
   assert.equal(result.results.length,10);assert.equal(result.paidProgress,0);assert.equal(result.balance,"0");
   const marked=result.results.filter(x=>x.paid_guaranteed);
   assert.equal(marked.length,1);assert.equal(marked[0].character_id,banners[p.banner].featured[0]);
  }
  const replays=await Promise.all(results.map(({p,payload})=>success(p,payload)));
  assert.ok(replays.every(r=>r.replayed&&r.balance==="0"));
  console.log(JSON.stringify({players:count,simultaneousRolls:count*10,elapsedMs:Math.round(elapsed),transactionsPerSecond:Math.round(count*1000/elapsed*10)/10,requestLatencyMs:metrics(times),databaseProbeMs:metrics(probeTimes),peakActive:maxActive,peakQueued:maxQueued}));
 }finally{clearInterval(watch);}
 assert.equal(summonAdmission.activeCount,0);assert.equal(summonAdmission.queuedCount,0);
 const states=await Promise.all(players.map(state));assert.ok(states.every(s=>s.paidTotal==="100"&&s.paidProgress===0&&s.currencies.paid_moonstones==="0"));
 const ledger=await pool.query("SELECT player_id,count(*)::int n,sum(delta)::int amount FROM currency_ledger WHERE player_id=ANY($1::uuid[]) AND currency_id='paid_moonstones' AND reason='gacha_pull' GROUP BY player_id",[playerIds]);
 assert.equal(ledger.rows.length,count);assert.ok(ledger.rows.every(r=>r.n===10&&r.amount===-12000));
 const marks=await pool.query("SELECT p.player_id,count(*)::int n FROM gacha_pull_results r JOIN gacha_pulls p ON p.id=r.pull_id WHERE p.player_id=ANY($1::uuid[]) AND r.reward_items @> '{\"paid_guaranteed\":true}'::jsonb GROUP BY p.player_id",[playerIds]);assert.equal(marks.rows.length,count);assert.ok(marks.rows.every(r=>r.n===1));
 console.log("PASS all 24 balances, 24 milestones, exact debits, replay and non-summon DB probes");
}finally{await app.close();await pool.query("DELETE FROM accounts WHERE email=ANY($1)",[emails]);await pool.end();console.log("Temporary accounts removed");}
