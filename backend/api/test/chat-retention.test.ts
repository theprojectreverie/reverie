import test from "node:test";
import assert from "node:assert/strict";
import {createChatRetention} from "../src/world/chat-retention.js";
test("retention drains full batches with a bounded cycle",async()=>{
 let calls=0;const job=createChatRetention(async()=>{calls++;return 1000;},()=>assert.fail());
 await job.tick();assert.equal(calls,10);await job.close();await job.tick();assert.equal(calls,10);
});
test("retention stops after partial batch and prevents overlapping cycles",async()=>{
 let calls=0;let release!:()=>void;
 const gate=new Promise<void>(r=>release=r);
 const job=createChatRetention(async()=>{calls++;await gate;return 12;},()=>assert.fail());
 const first=job.tick(),second=job.tick();assert.equal(first,second);assert.equal(calls,1);release();await Promise.all([first,second]);assert.equal(calls,1);await job.close();
});
test("retention recovers after a database failure",async()=>{
 let calls=0,errors=0;
 const job=createChatRetention(async()=>{if(++calls===1)throw new Error("temporary");return 0;},()=>{errors++;});
 await job.tick();await job.tick();assert.equal(errors,1);assert.equal(calls,2);await job.close();
});