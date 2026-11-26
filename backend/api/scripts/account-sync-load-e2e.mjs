import Fastify from "fastify";
import jwt from "@fastify/jwt";
import assert from "node:assert/strict";
import {randomBytes} from "node:crypto";
import {performance} from "node:perf_hooks";
import {config} from "../src/config.ts";
import {pool} from "../src/db.ts";
import {authRoutes} from "../src/routes/auth.ts";
import {summonRoutes} from "../src/routes/summon.ts";
assert.ok(["localhost","127.0.0.1","[::1]"].includes(new URL(config.DATABASE_URL).hostname));
const app=Fastify({logger:false}),suffix=randomBytes(5).toString("hex"),emails=[],players=[];
try{
 await app.register(jwt,{secret:config.JWT_SECRET});await app.register(authRoutes,{prefix:"/v1/auth"});await app.register(summonRoutes,{prefix:"/v1/summon"});await app.ready();
 const N=Number(process.env.QA_CLIENTS??24);assert.ok(Number.isInteger(N)&&N>=1&&N<=120);
 for(let i=0;i<N;i++){
  const email="load-"+suffix+"-"+i+"@example.test",name="Load"+suffix+i;emails.push(email);
  const a=(await pool.query("INSERT INTO accounts(email,password_hash,email_verified) VALUES($1,'disposable-test-no-login',true) RETURNING id,token_version",[email])).rows[0];
  const p=(await pool.query("INSERT INTO players(account_id,name) VALUES($1,$2) RETURNING id",[a.id,name])).rows[0];
  await pool.query("INSERT INTO player_currencies(player_id,currency_id,balance) VALUES($1,'gold',$2),($1,'crystals',$3)",[p.id,1000+i,120*(i+1)]);
  await pool.query("INSERT INTO inventory_items(player_id,item_id,quantity) VALUES($1,'moonpetal',$2)",[p.id,i+1]);
  players.push({id:p.id,token:app.jwt.sign({sub:a.id,playerId:p.id,tokenVersion:a.token_version}),gold:String(1000+i),crystals:String(120*(i+1)),petals:String(i+1)});
 }
 const durations=[],peak={waiting:0};let count=0;
 const check=async(p,path)=>{
  const start=performance.now();
  const res=await app.inject({url:path,headers:{authorization:"Bearer "+p.token}});
  durations.push(performance.now()-start);peak.waiting=Math.max(peak.waiting,pool.waitingCount);count++;
  assert.equal(res.statusCode,200);const b=res.json();assert.equal(b.playerId,p.id);assert.equal(b.currencies.gold,p.gold);assert.equal(b.currencies.crystals,p.crystals);
  if(path.endsWith("/state")){assert.equal(b.inventory.moonpetal,p.petals);assert.equal(b.roster.length,3);assert.deepEqual(b.party,["kael","gerald","lilith"]);}else{assert.equal(b.items.moonpetal,p.petals);assert.equal(b.gold,p.gold);}
 };
 for(let round=0;round<6;round++)await Promise.all(players.flatMap(p=>[check(p,"/v1/summon/state"),check(p,"/v1/auth/wallet")]));
 durations.sort((a,b)=>a-b);const pct=p=>Math.round(durations[Math.ceil(durations.length*p)-1]*10)/10;
 console.log(JSON.stringify({clients:N,requests:count,p50_ms:pct(.5),p95_ms:pct(.95),p99_ms:pct(.99),max_ms:pct(1),observed_pool_waiting:peak.waiting}));
 console.log("PASS concurrent wallet and collection reads, zero errors, account isolation");
 const targets=players.slice(0,Math.min(N,12));
 let writes=0,reads=0;
 const write=async p=>{
  const db=await pool.connect();
  try{
   await db.query("BEGIN");
   await db.query("UPDATE player_currencies SET balance=balance+1 WHERE player_id=$1 AND currency_id='gold'",[p.id]);
   await new Promise(resolve=>setTimeout(resolve,3));
   await db.query("UPDATE inventory_items SET quantity=quantity+1 WHERE player_id=$1 AND item_id='moonpetal'",[p.id]);
   await db.query("COMMIT");writes++;
  }catch(e){await db.query("ROLLBACK");throw e;}finally{db.release();}
 };
 const read=async(p,path)=>{
  const res=await app.inject({url:path,headers:{authorization:"Bearer "+p.token}});
  assert.equal(res.statusCode,200);const b=res.json();
  assert.equal(b.playerId,p.id);
  const items=b.inventory??b.items;
  assert.equal(BigInt(b.currencies.gold)-BigInt(items.moonpetal),999n,"mixed transaction snapshot");
  if(b.gold!==undefined)assert.equal(b.gold,b.currencies.gold);
  reads++;
 };
 for(let round=0;round<5;round++){
  await Promise.all([...targets.map(write),...players.flatMap(p=>[read(p,"/v1/summon/state"),read(p,"/v1/auth/wallet")])]);
 }
 for(const p of targets){
  const r=await app.inject({url:"/v1/summon/state",headers:{authorization:"Bearer "+p.token}});
  assert.equal(r.statusCode,200);assert.equal(r.json().currencies.gold,String(Number(p.gold)+5));assert.equal(r.json().inventory.moonpetal,String(Number(p.petals)+5));
 }
 assert.equal(pool.waitingCount,0);
 const recovery=performance.now();await Promise.all(players.slice(0,4).map(p=>read(p,"/v1/auth/wallet")));
 console.log(JSON.stringify({concurrent_snapshot_reads:reads,committed_reward_transactions:writes,recovery_probe_ms:Math.round((performance.now()-recovery)*10)/10,pool_waiting_after:pool.waitingCount}));
 console.log("PASS atomic read/write consistency, reward durability and post-burst pool recovery");
 const base=await app.listen({host:"127.0.0.1",port:0});
 const httpTimes=[];
 for(let round=0;round<3;round++){
  await Promise.all(players.map(async(p,index)=>{
   const path=(index+round)%2===0?"/v1/auth/wallet":"/v1/summon/state";
   const start=performance.now();
   const response=await fetch(base+path,{headers:{authorization:"Bearer "+p.token},signal:AbortSignal.timeout(10000)});
   assert.equal(response.status,200);const b=await response.json();
   assert.equal(b.playerId,p.id);
   assert.equal(BigInt(b.currencies.gold)-BigInt((b.items??b.inventory).moonpetal),999n);
   httpTimes.push(performance.now()-start);
  }));
 }
 httpTimes.sort((a,b)=>a-b);
 console.log(JSON.stringify({loopback_http_clients:N,requests:httpTimes.length,p50_ms:Math.round(httpTimes[Math.ceil(httpTimes.length*.5)-1]*10)/10,p95_ms:Math.round(httpTimes[Math.ceil(httpTimes.length*.95)-1]*10)/10,p99_ms:Math.round(httpTimes[Math.ceil(httpTimes.length*.99)-1]*10)/10,pool_waiting_after:pool.waitingCount}));
 console.log("PASS loopback HTTP burst, verified account snapshots");
}finally{await app.close();await pool.query("DELETE FROM accounts WHERE email=ANY($1::text[])",[emails]);const residue=await pool.query("SELECT count(*)::int AS n FROM accounts WHERE email=ANY($1::text[])",[emails]);await pool.end();assert.equal(residue.rows[0].n,0);console.log("PASS disposable test accounts cleaned up");}
