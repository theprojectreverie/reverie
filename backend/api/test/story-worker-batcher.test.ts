import test from "node:test";
import assert from "node:assert/strict";
import {StoryWorkerBatcher} from "../src/world/story-worker-batcher.js";
test("coalesces bounded jobs and preserves each response's identity",async()=>{
 const batches:number[][]=[];
 const b=new StoryWorkerBatcher<number,number>(async values=>{batches.push(values);return values.map(v=>v*2);},2,4,8,5,1000);
 const requests=Array.from({length:8},(_,i)=>b.submit(i));assert.equal(await b.submit(9),null);
 assert.deepEqual(await Promise.all(requests),[0,2,4,6,8,10,12,14]);assert.deepEqual(batches,[[0,1,2,3],[4,5,6,7]]);
 assert.equal(await b.submit(10),20);
});
test("failure or malformed result count cannot return another player's response",async()=>{
 let calls=0;const b=new StoryWorkerBatcher<number,number>(async values=>{calls++;if(calls===1)throw new Error("worker failed");if(calls===2)return [];return values;},1,4,4,5,1000);
 assert.deepEqual(await Promise.all([b.submit(1),b.submit(2)]),[null,null]);assert.equal(await b.submit(3),null);assert.equal(await b.submit(4),4);
});
test("expired waiting jobs are removed and capacity recovers",async()=>{
 let release!:()=>void;const barrier=new Promise<void>(r=>{release=r;});let started!:()=>void;const running=new Promise<void>(r=>{started=r;});
 const b=new StoryWorkerBatcher<number,number>(async values=>{started();await barrier;return values;},1,1,2,5,35);
 const a=b.submit(1);await running;const c=b.submit(2);assert.equal(await c,null);release();assert.equal(await a,1);assert.equal(await b.submit(3),3);
});
