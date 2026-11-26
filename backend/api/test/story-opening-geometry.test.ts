import test from "node:test";
import assert from "node:assert/strict";
import {readFileSync} from "node:fs";
import {openingRegion,openingContains,openingSpawn,openingEncounterInRange} from "../src/world/story-opening-geometry.js";
const scene=(path:string)=>readFileSync(new URL("../../../scenes/world/"+path,import.meta.url),"utf8");
function nodePosition(s:string,name:string){const block=s.split(/\n\[node /).find(v=>v.startsWith(`name="${name}"`));assert.ok(block);const m=block.match(/position = Vector2\(([-\d.]+), ([-\d.]+)\)/);assert.ok(m);return [Number(m[1]),Number(m[2])];}
test("opening geometry agrees with authored spawn and boss scene markers",()=>{
 const training=scene("tutorial_prologue/training_ground_v02.tscn"),village=scene("village/imported_village/village_playable.tscn"),map=scene("village/imported_village/village.tscn");
 assert.deepEqual(openingRegion("story_training_ground")?.spawn,nodePosition(training,"Kael"));
 assert.deepEqual(openingRegion("story_training_ground")?.encounter.position,nodePosition(training,"CompanionNPC"));
 assert.deepEqual(openingRegion("story_village")?.spawn,nodePosition(village,"SafeSpawnFromPreviousZone"));
 assert.deepEqual(openingRegion("story_village")?.encounter.position,nodePosition(map,"GeraldBossSpawn"));
 const outline=training.split(/\n\[node /).find(v=>v.startsWith('name="OuterSafetyOutline"'));assert.ok(outline);const coords=outline.match(/polygon = PackedVector2Array\(([^)]+)\)/)![1]!.split(',').map(Number);const offset=nodePosition(training,"OuterSafetyOutline");
 assert.deepEqual(openingRegion("story_training_ground")?.outline,Array.from({length:coords.length/2},(_,i)=>[coords[2*i]!+offset[0]!,coords[2*i+1]!+offset[1]!]));
 const vb=village.split(/\n\[node /).find(v=>v.startsWith('name="Bounds"'));assert.ok(vb);const v=vb.match(/polygon = PackedVector2Array\(([^)]+)\)/)![1]!.split(',').map(Number);assert.deepEqual(openingRegion("story_village")?.outline,Array.from({length:v.length/2},(_,i)=>[v[2*i],v[2*i+1]]));
});
test("opening regions reject out-of-outline proposals and wrong encounter ranges",()=>{
 assert.deepEqual(openingSpawn("story_training_ground"),{x:0,y:245});assert.deepEqual(openingSpawn("story_village"),{x:-2090,y:112});
 assert.ok(openingContains("story_training_ground",{x:0,y:245}));assert.ok(!openingContains("story_training_ground",{x:600,y:300}));assert.ok(openingContains("story_village",{x:2350,y:3700}));assert.ok(!openingContains("story_village",{x:2351,y:3700}));
 assert.ok(openingEncounterInRange("story_training_ground","tutorial_fairy_spar",{x:0,y:-82}));assert.ok(!openingEncounterInRange("story_training_ground","gerald_boss_encounter",{x:0,y:-82}));assert.ok(!openingEncounterInRange("story_village","gerald_boss_encounter",{x:114,y:2865}));assert.ok(!openingContains("__proto__",{x:0,y:0}));
});

test("garden solo region mirrors the authored diamond and entrance",()=>{
 const garden=scene("six_zone_reverie/individual_zones/zone_01_royal_gardens_standalone.tscn");
 const region=openingRegion("story_royal_gardens")!;
 assert.deepEqual(region.spawn,nodePosition(garden,"GardenEntrance"));
 assert.deepEqual(region.encounter.position,nodePosition(garden,"RoseSlime1"));
 const points=Array.from(garden.matchAll(/\[sub_resource type="SegmentShape2D" id="edge_[1-4]"\]\s+a = Vector2\(([-\d.]+), ([-\d.]+)\)/g),m=>[Number(m[1]),Number(m[2])]);
 assert.deepEqual(region.outline,points);assert.ok(openingContains("story_royal_gardens",{x:-1320,y:2325}));assert.ok(!openingContains("story_royal_gardens",{x:3000,y:3000}));
 assert.equal(openingRegion("story_village")?.nextRegion,"story_royal_gardens");assert.equal(openingRegion("six_zone_royal_gardens"),undefined);
});

test("Royal Gate story outline follows every authored perimeter segment",()=>{
 const gate=scene("six_zone_reverie/individual_zones/zone_02_royal_gate_standalone.tscn");const region=openingRegion("story_royal_gate")!;
 const points=Array.from(gate.matchAll(/\[sub_resource type="SegmentShape2D" id="edge_[^"]+"\]\s+a = Vector2\(([-\d.]+), ([-\d.]+)\)/g),m=>[Number(m[1]),Number(m[2])]);
 assert.deepEqual(region.outline,points);assert.deepEqual(region.spawn,nodePosition(gate,"SafeSpawnFromPreviousZone"));assert.deepEqual(region.encounter.position,nodePosition(gate,"Crownling01"));
 assert.ok(openingContains("story_royal_gate",{x:0,y:900}));assert.ok(openingContains("story_royal_gate",{x:1600,y:2510}));assert.ok(!openingContains("story_royal_gate",{x:3200,y:3000}));
});
