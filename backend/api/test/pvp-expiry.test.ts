import {test} from "node:test";
import assert from "node:assert/strict";
import type {PoolClient} from "pg";
import {expirePlayerMatches} from "../src/world/pvp-expiry.js";
test("expiry appends one terminal event then releases match and both tickets",async()=>{
 const calls:{sql:string;args:unknown[]}[]=[];
 let due=true;
 const db={query:async(sql:string,args:unknown[])=>{
  calls.push({sql,args});
  if(sql.startsWith("SELECT"))return {rows:due?[{id:"match",next_event_sequence:"7"}]:[]};
  if(sql.startsWith("UPDATE pvp_matches"))due=false;
  return {rows:[]};
 }} as unknown as PoolClient;
 assert.equal(await expirePlayerMatches(db,"player"),1);
 assert.match(calls[0]!.sql,/FOR UPDATE OF m/);
 assert.deepEqual(calls[1]!.args,["match",7,JSON.stringify({type:"match_expired",reason:"timeout"})]);
 assert.deepEqual(calls[2]!.args,["match",8,JSON.stringify({reason:"timeout",winnerId:null})]);
 assert.match(calls[3]!.sql,/UPDATE pvp_queue_tickets SET status='expired'/);
 assert.equal(await expirePlayerMatches(db,"player"),0);
 assert.equal(calls.length,5);
});
test("invalid event sequence stops before any expiry writes",async()=>{
 let writes=0;
 const db={query:async(sql:string)=>{
  if(sql.startsWith("SELECT"))return {rows:[{id:"match",next_event_sequence:"0"}]};
  writes++;return {rows:[]};
 }} as unknown as PoolClient;
 await assert.rejects(expirePlayerMatches(db,"player"),/event_sequence_exhausted/);
 assert.equal(writes,0);
});