import test from "node:test";
import assert from "node:assert/strict";
import Fastify from "fastify";
import {createRequestMetrics,createOperationalHistory,attachOperationalMetrics,requestMetrics,startOperationalSampling,operationalSnapshot} from "../src/world/operational-metrics.js";
test("bounded rolling histogram counts errors, throttles and ages out old samples",()=>{
 let clock=100000;const m=createRequestMetrics(()=>clock);
 assert.equal(m.snapshot().p95UpperMs,null);
 for(let i=0;i<95;i++)m.record(8,200);
 for(let i=0;i<4;i++)m.record(90,500);
 m.record(700,429);m.record(NaN,500);
 assert.deepEqual(m.snapshot(),{windowSeconds:60,requests:100,serverErrors:4,rateLimited:1,p50UpperMs:10,p95UpperMs:10});
 clock+=59000;m.record(180,200);assert.equal(m.snapshot().requests,101);
 clock+=1000;assert.equal(m.snapshot().requests,1);assert.equal(m.snapshot().p95UpperMs,200);
 clock+=60000;assert.equal(m.snapshot().requests,0);
});
test("Fastify response metrics observe successful and failed HTTP requests",async()=>{
 const app=Fastify();attachOperationalMetrics(app);
 app.get("/ok",async()=>({ok:true}));
 app.get("/error",async(_r,reply)=>reply.code(503).send({error:"unavailable"}));
 const before=requestMetrics.snapshot();
 await app.inject({url:"/ok"});await app.inject({url:"/error"});
 const after=requestMetrics.snapshot();
 assert.equal(after.requests-before.requests,2);assert.equal(after.serverErrors-before.serverErrors,1);
 await app.close();
});
test("database sampling reports failure and recovers, stops cleanly",async()=>{
 let fail=true,calls=0;
 const fake={query:async()=>{calls++;if(fail)throw Error("disconnected");},totalCount:3,idleCount:2,waitingCount:1} as any;
 const stop=startOperationalSampling(fake,5);
 try{
 await new Promise(r=>setTimeout(r,20));assert.equal(operationalSnapshot(fake).database.status,"unavailable");
 fail=false;await new Promise(r=>setTimeout(r,20));const m=operationalSnapshot(fake);
 assert.equal(m.database.status,"ok");assert.equal(m.database.poolWaiting,1);assert.ok(m.database.roundTripMs!==null);assert.equal(m.scope,"single_api_process");
 }finally{await stop();}
 const count=calls;await new Promise(r=>setTimeout(r,15));assert.equal(calls,count);
});

test("historical observations are bounded, copied and expire after one hour",()=>{
 let clock=100000;const h=createOperationalHistory(()=>clock,3);
 const sample={requests:1,p95UpperMs:10,serverErrors:0,rateLimited:0,databaseMs:null,databaseStatus:"unavailable",waiting:0,residentMiB:100};
 for(let i=0;i<4;i++){h.record(sample);clock+=15000;}
 assert.equal(h.snapshot().length,3);assert.equal(h.snapshot()[0]!.databaseMs,null);
 h.snapshot()[0]!.requests=999;assert.equal(h.snapshot()[0]!.requests,1);
 clock+=3600001;assert.equal(h.snapshot().length,0);
});
