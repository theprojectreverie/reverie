import test from "node:test";
import assert from "node:assert/strict";
import Fastify from "fastify";
import jwt from "@fastify/jwt";
import {randomUUID} from "node:crypto";

// Configuration is provided solely for module initialization. No DB connection
// is needed: the routes must reject before accessing a database.
process.env.DATABASE_URL??="postgres://localhost/reverie_test";
process.env.JWT_SECRET??="test-secret-that-is-long-enough-for-jwt";
const {makeCompensationRoutes}=await import("../src/routes/compensation.js");

test("compensation endpoints deny unauthenticated and unlisted accounts by default",async()=>{
 const app=Fastify();
 await app.register(jwt,{secret:"isolated-test-secret"});
 await app.register(makeCompensationRoutes(""),{prefix:"/admin"});
 try{
  const signed=app.jwt.sign({sub:randomUUID(),playerId:randomUUID(),tokenVersion:1});
  assert.equal((await app.inject({url:"/admin/reviews"})).statusCode,401);
  assert.equal((await app.inject({url:"/admin/reviews",headers:{authorization:"Bearer "+signed}})).statusCode,403);
  assert.equal((await app.inject({method:"POST",url:"/admin/decide",headers:{authorization:"Bearer "+signed},payload:{pullId:randomUUID(),rollIndex:9,action:"approve",note:"fixture"}})).statusCode,403);
 }finally{await app.close();}
});

test("developer-like identity cannot grant itself permissions via token claims",async()=>{
 const app=Fastify();await app.register(jwt,{secret:"isolated-test-secret"});
 await app.register(makeCompensationRoutes(randomUUID()),{prefix:"/admin"});
 try{
  const signed=app.jwt.sign({sub:randomUUID(),playerId:randomUUID(),tokenVersion:1,role:"admin"});
  assert.equal((await app.inject({url:"/admin/reviews",headers:{authorization:"Bearer "+signed}})).statusCode,403);
 }finally{await app.close();}
});
