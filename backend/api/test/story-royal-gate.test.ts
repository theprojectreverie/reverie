import test from "node:test";
import assert from "node:assert/strict";
import {gatePatrolProgress} from "../src/world/story-royal-gate.js";
import {evaluateStoryEncounter,isGardenEncounter,isGateEncounter} from "../src/world/story-encounter-admission.js";
test("gate objective counts distinct authored encounters and requires settlement",()=>{
 const a="royal_gate_patrol_1",b="royal_gate_patrol_2";
 assert.equal(gatePatrolProgress([a,a],false).progress,1);
 assert.equal(gatePatrolProgress([a,b],false).willowFieldsUnlocked,false);
 assert.equal(gatePatrolProgress([a,b],true).willowFieldsUnlocked,true);
 assert.equal(gatePatrolProgress([a],true).willowFieldsUnlocked,false);
 assert.equal(isGardenEncounter(a),false);assert.equal(isGateEncounter("crownling_garden_1"),false);
});
test("gate encounters require the separate region and audience proof",()=>{
 const proof={region:"story_royal_gate",x:-65,y:1200,live:true,fresh:true,victories:["tutorial_fairy_spar","gerald_boss_encounter","mirene_encounter"],coolingDown:false,audienceComplete:true};
 assert.deepEqual(evaluateStoryEncounter("royal_gate_patrol_1",proof),{ok:true});
 assert.deepEqual(evaluateStoryEncounter("royal_gate_patrol_1",{...proof,victories:proof.victories.filter(id=>id!=="mirene_encounter")}),{ok:false,reason:"encounter_progression_required"});
 assert.deepEqual(evaluateStoryEncounter("royal_gate_patrol_1",{...proof,audienceComplete:false}),{ok:false,reason:"encounter_progression_required"});
 assert.deepEqual(evaluateStoryEncounter("royal_gate_patrol_2",proof),{ok:false,reason:"encounter_out_of_range"});
 assert.deepEqual(evaluateStoryEncounter("royal_gate_patrol_1",{...proof,region:"six_zone_royal_gate"}),{ok:false,reason:"wrong_encounter_region"});
});
