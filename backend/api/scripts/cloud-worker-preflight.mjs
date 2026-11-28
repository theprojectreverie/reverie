import assert from "node:assert/strict";
import {performance} from "node:perf_hooks";
import {config} from "../src/config.ts";
import {replayStoryCombat} from "../src/world/story-combat-service.ts";
import {pool} from "../src/db.ts";
// Synthetic combat inputs only; no account creation, database writes, or player data.
assert.equal(config.REVERIE_STORY_WORKER_CONCURRENCY,1,"small-host preflight requires one worker");
assert.ok(process.env.REVERIE_STORY_GODOT,"headless Godot runtime must be configured");
const input={seed:13579,party:[{char_id:"kael",level:1,xp:"0",ascension:0,awakening:0,bond:0,dupes:0,skill_levels:{},equipment:[]}],collectionCount:3,actions:[]};
const group="tutorial_fairy_spar";
try{
 const start=performance.now();
 const [a,b]=await Promise.all([replayStoryCombat(group,input),replayStoryCombat(group,input)]);
 assert.ok(a.ok,JSON.stringify(a));assert.ok(b.ok,JSON.stringify(b));
 assert.equal(a.status,"active");assert.equal(a.sequence,0);assert.deepEqual(a,b);
 const action={kind:"defend",actorUid:a.actorUid};
 const [x,y]=await Promise.all([replayStoryCombat(group,{...input,actions:[action]}),replayStoryCombat(group,input)]);
 assert.ok(x.ok,JSON.stringify(x));assert.equal(x.sequence,1);
 assert.deepEqual(y,b);assert.deepEqual(await replayStoryCombat(group,{...input,actions:[action]}),x);
 console.log(JSON.stringify({ok:true,mode:process.env.REVERIE_STORY_BATCH_WORKERS==="1"?"batch":"single",workerConcurrency:1,elapsedMs:Math.round(performance.now()-start),checks:["two simultaneous deterministic sessions","isolated action result","deterministic replay"]}));
}finally{await pool.end();}