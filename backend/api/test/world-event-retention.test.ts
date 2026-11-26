import test from "node:test";
import assert from "node:assert/strict";
import {startWorldEventRetention,WORLD_EVENT_RETENTION_SQL,WORLD_POSITION_RETENTION_SQL} from "../src/world/world-event-retention.js";
const sleep=(ms:number)=>new Promise(resolve=>setTimeout(resolve,ms));
test("world retention preserves the existing age threshold and recent cursor floor",()=>{
 assert.match(WORLD_EVENT_RETENTION_SQL,/interval '30 days'/);
 assert.match(WORLD_EVENT_RETENTION_SQL,/next_event_sequence-1000/);
 assert.match(WORLD_EVENT_RETENTION_SQL,/LIMIT 1000 FOR UPDATE OF e SKIP LOCKED/);
});
test("shorter retention applies only to positions and keeps the cursor floor",()=>{
 assert.match(WORLD_POSITION_RETENTION_SQL,/make_interval\(hours=>\$1::int\)/);
 assert.match(WORLD_POSITION_RETENTION_SQL,/event_type='position' OR e.created_at<now\(\)-interval '30 days'/);
 assert.match(WORLD_POSITION_RETENTION_SQL,/next_event_sequence-1000/);
});
test("bounded cleanup cycles stop on partial batches",async()=>{
 let calls=0,removed=0;
 const stop=startWorldEventRetention(async()=>++calls===1?1000:12,n=>{removed=n;},()=>assert.fail(),10000);
 await sleep(10);await stop();
 assert.equal(calls,2);assert.equal(removed,1012);
});
test("overlapping ticks are blocked and shutdown waits for pending cleanup",async()=>{
 let calls=0;let release!:()=>void;
 const gate=new Promise<void>(r=>{release=r;});
 const stop=startWorldEventRetention(async()=>{calls++;await gate;return 1000;},()=>{},()=>assert.fail(),2);
 await sleep(15);assert.equal(calls,1);
 let finished=false;const stopping=stop().then(()=>{finished=true;});
 await sleep(5);assert.equal(finished,false);release();await stopping;
 assert.equal(calls,1);
});
test("cleanup retries after a failure",async()=>{
 let calls=0,errors=0;
 const stop=startWorldEventRetention(async()=>{if(++calls===1)throw Error("temporary");return 0;},()=>{},()=>{errors++;},5);
 await sleep(35);await stop();assert.equal(errors,1);assert.ok(calls>=2);
});
