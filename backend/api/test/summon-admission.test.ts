import test from "node:test";
import assert from "node:assert/strict";
import {SummonAdmission} from "../src/world/summon-admission.js";
test("admission preserves parallel capacity and serializes one player",async()=>{
 const gate=new SummonAdmission(2,3,500);
 const a=await gate.acquire("a");assert.ok(a);
 const repeat=gate.acquire("a");
 const b=await gate.acquire("b");assert.ok(b);assert.equal(gate.activeCount,2);
 const c=gate.acquire("c");assert.equal(gate.queuedCount,2);
 b();const cLease=await c;assert.ok(cLease);assert.equal(gate.queuedCount,1);
 a();const a2=await repeat;assert.ok(a2);a2();cLease();assert.equal(gate.activeCount,0);
});
test("bounded queue rejects excess and expires waiting leases",async()=>{
 const gate=new SummonAdmission(1,1,25);
 const a=await gate.acquire("a");assert.ok(a);
 const b=gate.acquire("b");assert.equal(await gate.acquire("c"),null);assert.equal(await b,null);
 a();assert.equal(gate.activeCount,0);assert.equal(gate.queuedCount,0);
});
