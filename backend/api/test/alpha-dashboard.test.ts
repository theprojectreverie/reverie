import test from "node:test";
import assert from "node:assert/strict";
import Fastify from "fastify";
import jwt from "@fastify/jwt";
import {createDeveloperRoutes} from "../src/routes/developer.js";
import {probeAlphaHealth} from "../src/world/alpha-dashboard.js";

test("alpha health distinguishes open, maintenance, invalid and failed probes",async()=>{
 const probe=async(body:unknown,status=200)=>probeAlphaHealth("https://example.test/health",async(_url,options)=>{
  assert.equal(options?.redirect,"error");
  assert.ok(options?.signal);
  return new Response(JSON.stringify(body),{status});
 });
 assert.equal((await probe({service:"Reverie",status:"ok",gameplayOpen:true})).state,"open");
 assert.equal((await probe({service:"Reverie",status:"ok",gameplayOpen:false})).state,"closed");
 assert.equal((await probe({service:"other",status:"ok",gameplayOpen:true})).state,"unknown");
 assert.equal((await probe({status:"unavailable"},503)).state,"unavailable");
 assert.equal((await probeAlphaHealth("https://example.test/health",async()=>{throw Error("network failure")})).state,"unavailable");
});
test("alpha infrastructure requires active developer session and returns aggregates only",async()=>{
 const owner="11111111-1111-4111-8111-111111111111",player="22222222-2222-4222-8222-222222222222";
 const app=Fastify();await app.register(jwt,{secret:"alpha-dashboard-test-secret-long-enough"});
 let reads=0,snapshots=0;
 const probe={state:"open" as const,httpStatus:200,durationMs:12,checkedAt:new Date().toISOString()};
 const alpha={network:{public:probe,local:probe},enrollment:{enrolled:2,active:2,unused:1,consumed:2,issuanceLimit:20,remaining:17},recentPresence:2,recentLobbies:1,realtime:{connections:2,players:2,lobbies:1},scope:"host_probe_and_single_api_process",restrictions:{inviteOnly:true,paidPurchases:false,paidSummons:false,persistentRegionalWorld:false},asOf:probe.checkedAt};
 await app.register(createDeveloperRoutes({developerAccountIds:owner,database:{query:async sql=>{reads++;return {rows:sql.includes("SELECT a.token_version")?[{status:"active",token_version:1}]:[{}]}}},alphaSnapshot:async()=>{snapshots++;return alpha}}));
 const path="/v1/developer/server-health",get=(sub:string,version:number)=>app.inject({url:path,headers:{authorization:"Bearer "+app.jwt.sign({sub,playerId:player,tokenVersion:version})}});
 assert.equal((await app.inject({url:path})).statusCode,401);
 assert.equal((await get("33333333-3333-4333-8333-333333333333",1)).statusCode,403);
 assert.equal(reads,0);assert.equal(snapshots,0);
 assert.equal((await get(owner,0)).statusCode,401);assert.equal(snapshots,0);
 const ok=await get(owner,1);assert.equal(ok.statusCode,200);assert.deepEqual(ok.json().alpha,alpha);assert.equal(snapshots,1);
 assert.equal(ok.headers["cache-control"],"no-store");
 assert.doesNotMatch(JSON.stringify(ok.json().alpha),/token_hash|password|playerId|used_by|email/);
 await app.close();
});