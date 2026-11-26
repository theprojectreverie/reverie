import test from "node:test";
import assert from "node:assert/strict";
import {StoryWorkerQueue} from "../src/world/story-worker-queue.js";

test("FIFO admits only bounded work and releases a slot exactly once",async()=>{
 const q=new StoryWorkerQueue(2,2,1000);
 const a=await q.acquire(),b=await q.acquire();assert.ok(a&&b);
 const order:string[]=[];
 const c=q.acquire().then(r=>{order.push("c");return r;});
 const d=q.acquire().then(r=>{order.push("d");return r;});
 assert.equal(await q.acquire(),null);assert.deepEqual(order,[]);
 a();a();const cRelease=await c;assert.ok(cRelease);assert.deepEqual(order,["c"]);
 b();const dRelease=await d;assert.ok(dRelease);assert.deepEqual(order,["c","d"]);
 cRelease();dRelease();const e=await q.acquire();assert.ok(e);e();
});
test("timed-out waiters are removed without taking a worker slot",async()=>{
 const q=new StoryWorkerQueue(1,1,20);
 const a=await q.acquire();assert.ok(a);
 assert.equal(await q.acquire(),null);
 const b=q.acquire();a();const release=await b;assert.ok(release);release();
 const c=await q.acquire();assert.ok(c);c();
});
test("invalid queue limits fail closed",()=>{
 assert.throws(()=>new StoryWorkerQueue(0,1,100));assert.throws(()=>new StoryWorkerQueue(1,-1,100));assert.throws(()=>new StoryWorkerQueue(1,1,0));
});
