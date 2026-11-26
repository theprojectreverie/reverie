import assert from "node:assert/strict";
import {randomBytes} from "node:crypto";
import Fastify from "fastify";
import jwt from "@fastify/jwt";
import rateLimit from "@fastify/rate-limit";
import {pool} from "../src/db.ts";
import {config} from "../src/config.ts";
import {createSharedRateLimitStore,pruneSharedRateLimits} from "../src/world/shared-rate-limit.ts";
import {gameServerRoutes} from "../src/routes/game-servers.ts";
assert.ok(config.NODE_ENV!=="production"&&["127.0.0.1","localhost","[::1]"].includes(new URL(config.DATABASE_URL).hostname));
const namespace="quota_qa_"+randomBytes(6).toString("hex"),apps=[],secret=config.JWT_SECRET;
const make=async()=>{
 const app=Fastify({logger:false});apps.push(app);
 await app.register(rateLimit,{max:5,timeWindow:60000,store:createSharedRateLimitStore(pool,namespace,secret),skipOnError:false});
 await app.register(jwt,{secret});
 app.get("/global",async()=>({ok:true}));app.get("/other",async()=>({ok:true}));
 app.get("/route/:id",{config:{rateLimit:{max:3,timeWindow:60000}}},async()=>({ok:true}));
 app.get("/separate",{config:{rateLimit:{max:3,timeWindow:60000}}},async()=>({ok:true}));
 app.get("/short",{config:{rateLimit:{max:1,timeWindow:100}}},async()=>({ok:true}));
 await app.register(gameServerRoutes,{prefix:"/v1/game-servers"});await app.ready();return app;
};
try{
 const a=await make(),b=await make();
 const burst=await Promise.all(Array.from({length:20},(_,i)=>(i%2?a:b).inject({url:i%3?"/global":"/other"})));
 assert.equal(burst.filter(r=>r.statusCode===200).length,5);
 assert.equal(burst.filter(r=>r.statusCode===429).length,15);
 const routes=await Promise.all(Array.from({length:9},(_,i)=>(i%2?a:b).inject({url:"/route/"+i})));
 assert.equal(routes.filter(r=>r.statusCode===200).length,3);assert.equal(routes.filter(r=>r.statusCode===429).length,6);
 assert.equal((await b.inject({url:"/separate"})).statusCode,200);
 assert.equal((await a.inject({url:"/short"})).statusCode,200);assert.equal((await b.inject({url:"/short"})).statusCode,429);
 await new Promise(r=>setTimeout(r,130));assert.equal((await b.inject({url:"/short"})).statusCode,200);
 // Real join route checks verified JWT identity before applying its 10/min quota.
 const auth=(sub)=>a.jwt.sign({sub,playerId:"22222222-2222-4222-8222-222222222222",tokenVersion:1});
 const first=auth("11111111-1111-4111-8111-111111111111"),second=auth("33333333-3333-4333-8333-333333333333");
 const join=(app,t)=>app.inject({method:"POST",url:"/v1/game-servers/44444444-4444-4444-8444-444444444444/join",headers:{authorization:"Bearer "+t},payload:{}});
 const player=await Promise.all(Array.from({length:15},(_,i)=>join(i%2?a:b,first)));
 assert.equal(player.filter(r=>r.statusCode===429).length,5);
 assert.equal(player.filter(r=>r.statusCode===401).length,10);
 assert.equal((await join(b,second)).statusCode,401);
 // The store must survive replacement of an API process.
 await a.close();const c=await make();assert.equal((await c.inject({url:"/global"})).statusCode,429);
 const rows=await pool.query("SELECT bucket_hash,hits FROM api_rate_limit_buckets WHERE namespace=$1",[namespace]);
 assert.ok(rows.rows.every(r=>/^[0-9a-f]{64}$/.test(r.bucket_hash)&&r.hits>=1));
 const expired=randomBytes(32).toString("hex");
 await pool.query("INSERT INTO api_rate_limit_buckets(namespace,bucket_hash,hits,expires_at) VALUES($1,$2,1,now()-interval '2 minutes')",[namespace,expired]);
 assert.equal(await pruneSharedRateLimits(pool,namespace),1);
 assert.equal((await c.inject({url:"/global"})).statusCode,429);
 const broken={query:async()=>{throw Error("private error detail");}};
 const d=Fastify();apps.push(d);await d.register(rateLimit,{max:1,store:createSharedRateLimitStore(broken,namespace,secret),skipOnError:false});d.get("/",async()=>({ok:true}));
 const unavailable=await d.inject({url:"/"});assert.equal(unavailable.statusCode,503);assert.ok(!unavailable.body.includes("private error detail"));
 console.log("PASS atomic cross-instance global and route quotas, window expiry, real JWT player isolation, restart continuity, cleanup, hashed identities and fail-closed outage");
}finally{
 for(const app of apps)await app.close().catch(()=>{});
 await pool.query("DELETE FROM api_rate_limit_buckets WHERE namespace=$1",[namespace]);await pool.end();console.log("PASS quota fixtures removed");
}
