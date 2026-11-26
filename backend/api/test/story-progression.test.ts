import test from "node:test";
import assert from "node:assert/strict";
import Fastify from "fastify";
import jwt from "@fastify/jwt";
import {createStoryProgressionRoutes} from "../src/routes/story-progression.js";

const secret="story-progression-test-secret-at-least-32-characters";
const account="11111111-1111-4111-8111-111111111111";
const player="22222222-2222-4222-8222-222222222222";

test("milestone endpoint requires a valid signed-in session and strict milestone input",async()=>{
 let queryCount=0;
 const app=Fastify();
 await app.register(jwt,{secret});
 await app.register(createStoryProgressionRoutes({database:{query:async()=>{queryCount++;return{rows:[]};}}}),{prefix:"/v1/progression"});
 const anonymous=await app.inject({method:"POST",url:"/v1/progression/milestones",payload:{milestoneId:"village"}});
 assert.equal(anonymous.statusCode,401);
 const token=app.jwt.sign({sub:account,playerId:player,tokenVersion:1});
 const invalid=await app.inject({method:"POST",url:"/v1/progression/milestones",headers:{authorization:`Bearer ${token}`},payload:{milestoneId:"not_a_story_milestone"}});
 assert.equal(invalid.statusCode,400);
 const extraIdentity=await app.inject({method:"POST",url:"/v1/progression/milestones",headers:{authorization:`Bearer ${token}`},payload:{milestoneId:"village",playerId:"33333333-3333-4333-8333-333333333333"}});
 assert.equal(extraIdentity.statusCode,400);
 assert.equal(queryCount,0,"invalid requests must not access the database");
 await app.close();
});

test("milestone reaches are idempotent and identity comes from the current account session",async()=>{
 const stored=new Set<string>();
 const statements:string[]=[];
 const app=Fastify();
 await app.register(jwt,{secret});
 await app.register(createStoryProgressionRoutes({database:{query:async(sql,values)=>{
  statements.push(sql);
  const key=`${values?.[0]}:${values?.[3]}`;
  const recorded=!stored.has(key);
  if(recorded)stored.add(key);
  return{rows:[{authorized:true,recorded}]};
 }}}),{prefix:"/v1/progression"});
 const token=app.jwt.sign({sub:account,playerId:player,tokenVersion:9});
 const post=()=>app.inject({method:"POST",url:"/v1/progression/milestones",headers:{authorization:`Bearer ${token}`},payload:{milestoneId:"royal_gardens"}});
 const first=await post();
 const retry=await post();
 assert.equal(first.statusCode,200);
 assert.deepEqual(first.json(),{milestoneId:"royal_gardens",recorded:true});
 assert.equal(retry.statusCode,200);
 assert.deepEqual(retry.json(),{milestoneId:"royal_gardens",recorded:false});
 assert.equal(stored.size,1);
 assert.match(statements[0]!,/a\.token_version=\$3/);
 assert.match(statements[0]!,/ON CONFLICT\(player_id,milestone_id\) DO NOTHING/);
 await app.close();
});

test("revoked or inactive accounts cannot record milestone reaches",async()=>{
 const app=Fastify();
 await app.register(jwt,{secret});
 await app.register(createStoryProgressionRoutes({database:{query:async()=>({rows:[{authorized:false,recorded:false}]})}}),{prefix:"/v1/progression"});
 const token=app.jwt.sign({sub:account,playerId:player,tokenVersion:8});
 const response=await app.inject({method:"POST",url:"/v1/progression/milestones",headers:{authorization:`Bearer ${token}`},payload:{milestoneId:"chapter_complete"}});
 assert.equal(response.statusCode,401);
 assert.equal(response.json().error,"session_revoked");
 await app.close();
});
