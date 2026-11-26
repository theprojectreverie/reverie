import Fastify from "fastify";
import jwt from "@fastify/jwt";
import assert from "node:assert/strict";
import {randomBytes,randomUUID} from "node:crypto";
import {config} from "../src/config.ts";
import {pool} from "../src/db.ts";
import {authRoutes} from "../src/routes/auth.ts";
import {summonRoutes} from "../src/routes/summon.ts";
import {banners} from "../src/world/summon.ts";

assert.ok(["localhost","127.0.0.1","[::1]"].includes(new URL(config.DATABASE_URL).hostname),"Local fixture database only");
const app=Fastify({logger:false}), emails=[];
const ids=Object.keys(banners);
async function call(token,method,url,payload){
 return app.inject({method,url,headers:token?{authorization:"Bearer "+token}:{},...(payload?{payload}:{})});
}
async function fixture(){
 const name="QaRace"+randomBytes(5).toString("hex"),email=name.toLowerCase()+"@example.test",password=randomBytes(16).toString("hex");emails.push(email);
 const body={playerName:name,password};
 assert.equal((await call("","POST","/v1/auth/register",{...body,email})).statusCode,201);
 const a=(await call("","POST","/v1/auth/login",body)).json(),b=(await call("","POST","/v1/auth/login",body)).json();
 assert.equal(a.player.id,b.player.id);
 return {id:a.player.id,a:a.accessToken,b:b.accessToken};
}
const request=(bannerId,count=10,currency="paid_moonstones")=>({bannerId,count,currency,requestId:randomUUID()});
const pull=(token,payload)=>call(token,"POST","/v1/summon/pull",payload);
async function state(t){const r=await call(t,"GET","/v1/summon/state");assert.equal(r.statusCode,200,r.body);return r.json();}
async function successful(t,p){const r=await pull(t,p);assert.equal(r.statusCode,200,r.body);return r.json();}
try{
 await app.register(jwt,{secret:config.JWT_SECRET});
 await app.register(authRoutes,{prefix:"/v1/auth"});
 await app.register(summonRoutes,{prefix:"/v1/summon"});
 const f=await fixture();
 await pool.query("INSERT INTO player_currencies(player_id,currency_id,balance) VALUES($1,'paid_moonstones',13200),($1,'crystals',1200) ON CONFLICT(player_id,currency_id) DO UPDATE SET balance=EXCLUDED.balance",[f.id]);
 for(let i=0;i<9;i++)await successful(f.a,request(ids[i%ids.length]));
 assert.equal((await state(f.a)).paidProgress,90);
 assert.equal((await state(f.b)).paidProgress,90);
 const jobs=[{token:f.a,p:request(ids[0])},{token:f.b,p:request(ids[1])},{token:f.b,p:request(ids[2],10,"crystals")}];
 const replies=await Promise.all(jobs.map(j=>successful(j.token,j.p)));
 const marked=replies.flatMap((r,i)=>r.results.filter(v=>v.paid_guaranteed).map(v=>({result:v,job:jobs[i]})));
 assert.equal(marked.length,1);
 assert.equal(marked[0].result.index,9);
 assert.equal(marked[0].result.character_id,banners[marked[0].job.p.bannerId].featured[0]);
 const s1=await state(f.a),s2=await state(f.b);assert.deepEqual(s1,s2);
 assert.equal(s1.paidProgress,10);assert.equal(s1.currencies.paid_moonstones,"0");assert.equal(s1.currencies.crystals,"0");
 const before=await state(f.a);
 const replay=await Promise.all([successful(f.a,jobs[0].p),successful(f.b,jobs[0].p)]);
 assert.ok(replay.every(r=>r.replayed&&r.paidProgress===10&&r.balance==="0"));
 assert.deepEqual(replay[0].results,replies[0].results);
 assert.deepEqual(await state(f.b),before);
 const blocked=await pull(f.b,request(ids[2]));assert.equal(blocked.statusCode,409);
 const ledger=await pool.query("SELECT count(*)::int n,COALESCE(sum(delta),0)::int amount FROM currency_ledger WHERE player_id=$1 AND currency_id='paid_moonstones' AND reason='gacha_pull'",[f.id]);assert.deepEqual(ledger.rows[0],{n:11,amount:-13200});
 console.log("PASS simultaneous distinct paid banners, free pull, one milestone, exact debit, cross-session replay");
 const g=await fixture();
 await pool.query("INSERT INTO player_currencies(player_id,currency_id,balance) VALUES($1,'paid_moonstones',1200) ON CONFLICT(player_id,currency_id) DO UPDATE SET balance=EXCLUDED.balance",[g.id]);
 const competing=await Promise.all([pull(g.a,request(ids[0])),pull(g.b,request(ids[1]))]);
 assert.deepEqual(competing.map(r=>r.statusCode).sort(),[200,409]);
 const gs=await state(g.b);assert.equal(gs.paidProgress,10);assert.equal(gs.currencies.paid_moonstones,"0");
 assert.deepEqual(await state(f.a),before);
 console.log("PASS competing requests for final available funds, no overdraft, separate account isolation");
 const h=await fixture();
 await pool.query("INSERT INTO player_currencies(player_id,currency_id,balance) VALUES($1,'paid_moonstones',13200) ON CONFLICT(player_id,currency_id) DO UPDATE SET balance=EXCLUDED.balance",[h.id]);
 for(let i=0;i<9;i++)await successful(h.a,request(ids[i%ids.length]));
 const observed=await state(h.a);assert.equal(observed.paidTotal,"90");
 const contenders=[{...request(ids[0]),expectedPaidTotal:observed.paidTotal},{...request(ids[1]),expectedPaidTotal:observed.paidTotal}];
 const races=await Promise.all([pull(h.a,contenders[0]),pull(h.b,contenders[1])]);
 assert.deepEqual(races.map(r=>r.statusCode).sort(),[200,409]);
 const win=races.findIndex(r=>r.statusCode===200),lose=1-win;
 assert.equal(races[lose].json().error,"paid_progress_changed");
 assert.equal(races[win].json().results[9].character_id,banners[contenders[win].bannerId].featured[0]);
 const afterRace=await state(h.b);assert.equal(afterRace.paidTotal,"100");assert.equal(afterRace.paidProgress,0);assert.equal(afterRace.currencies.paid_moonstones,"1200");
 const again=await successful(h.b,contenders[win]);assert.equal(again.replayed,true);assert.equal(again.balance,"1200");
 assert.deepEqual(await state(h.a),afterRace);
 const retry=await successful(h.b,{...request(contenders[lose].bannerId),expectedPaidTotal:afterRace.paidTotal});assert.equal(retry.paidProgress,10);assert.equal(retry.balance,"0");assert.ok(!retry.results.some(r=>r.paid_guaranteed));
 console.log("PASS stale paid counter rejection without debit, replay before freshness check, fresh retry");
}finally{
 await app.close();
 await pool.query("DELETE FROM accounts WHERE email=ANY($1)",[emails]);
 await pool.end();
 console.log("Temporary fixture accounts removed");
}
