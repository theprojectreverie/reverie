import test from "node:test";
import assert from "node:assert/strict";
import {evaluateStoryEncounter} from "../src/world/story-encounter-admission.js";
const id="rose_slime_garden_1";
const proof={region:"six_zone_royal_gardens",x:-1100,y:2200,live:true,fresh:true,victories:["tutorial_fairy_spar","gerald_boss_encounter"],coolingDown:false};
test("pilot admits an authored encounter only within its range",()=>{
 assert.deepEqual(evaluateStoryEncounter(id,proof),{ok:true});
 assert.deepEqual(evaluateStoryEncounter(id,{...proof,x:proof.x+113}),{ok:true});
 assert.deepEqual(evaluateStoryEncounter(id,{...proof,x:proof.x+114}),{ok:false,reason:"encounter_out_of_range"});
 assert.deepEqual(evaluateStoryEncounter(id,{...proof,x:NaN}),{ok:false,reason:"encounter_out_of_range"});
 assert.deepEqual(evaluateStoryEncounter(id,{...proof,region:"castle_royal_gardens"}),{ok:false,reason:"wrong_encounter_region"});
});
test("unverified position, missing verified progression and respawn are rejected",()=>{
 for(const p of [null,{...proof,live:false},{...proof,fresh:false}])assert.deepEqual(evaluateStoryEncounter(id,p),{ok:false,reason:"world_position_unverified"});
 assert.deepEqual(evaluateStoryEncounter(id,{...proof,victories:["village"]}),{ok:false,reason:"encounter_progression_required"});
 assert.deepEqual(evaluateStoryEncounter(id,{...proof,victories:["gerald_boss_encounter"]}),{ok:false,reason:"encounter_progression_required"});
 assert.deepEqual(evaluateStoryEncounter(id,{...proof,coolingDown:true}),{ok:false,reason:"encounter_respawning"});
});
test("arbitrary boss and prototype names are denied by default",()=>{
 for(const group of ["revienna_encounter","cassien_encounter","gerald_boss_encounter","tutorial_fairy_spar","__proto__","constructor","unknown"])assert.deepEqual(evaluateStoryEncounter(group,proof),{ok:false,reason:"encounter_not_enabled"});
});
