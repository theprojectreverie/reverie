import test from "node:test";
import assert from "node:assert/strict";
import {cassienSpecial} from "../src/world/cassien-special.js";
test("Cassien telegraphs exactly two server-defined threshold attacks",()=>{
 assert.deepEqual(cassienSpecial(400,"p1",1000),{name:"Crimson Crescent",targetId:"p1",resolveAt:2800,damage:26});
 assert.deepEqual(cassienSpecial(200,"p2",1000),{name:"Crimson Requiem",targetId:"p2",resolveAt:3400,damage:40});
 for(const hp of [600,500,300,100,0]) assert.equal(cassienSpecial(hp,"p1",1000),null);
});
