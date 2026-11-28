import test from "node:test";
import assert from "node:assert/strict";
import Fastify from "fastify";
import rateLimit from "@fastify/rate-limit";
process.env.DATABASE_URL??="postgres://localhost/reverie_test";
process.env.JWT_SECRET??="test-secret-that-is-long-enough-for-jwt";
const {alphaLoginRateKey}=await import("../src/world/alpha-access.js");

test("alpha login quota is isolated by normalized username and still limits repeated attempts",async()=>{
 const app=Fastify();
 await app.register(rateLimit,{global:false});
 app.post("/login",{config:{rateLimit:{max:8,timeWindow:"15 minutes",hook:"preHandler",keyGenerator:req=>alphaLoginRateKey(app,req)}}},async()=>({ok:true}));
 try{
  const login=(playerName:string)=>app.inject({method:"POST",url:"/login",headers:{"x-reverie-alpha":"1"},payload:{playerName,password:"not-a-real-password"}});
  for(let i=0;i<8;i++)assert.equal((await login(i%2?"ExampleOne":"exampleone")).statusCode,200);
  assert.equal((await login(" EXAMPLEONE ")).statusCode,429);
  assert.equal((await login("ExampleTwo")).statusCode,200);
 }finally{await app.close();}
});
