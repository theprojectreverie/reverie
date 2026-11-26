import test from "node:test";
import assert from "node:assert/strict";
import {readFileSync} from "node:fs";
import {audienceTransition,ELATHRA_POSITION} from "../src/world/story-elathra.js";
import {openingContains} from "../src/world/story-opening-geometry.js";
test("Elathra dialogue advances in order and never rewards replays",()=>{
 assert.deepEqual(audienceTransition("not_started","accept"),{ok:false,reason:"audience_hear_first"});
 assert.deepEqual(audienceTransition("not_started","hear"),{ok:true,state:"active",replayed:false});
 assert.deepEqual(audienceTransition("active","hear"),{ok:true,state:"active",replayed:true});
 assert.deepEqual(audienceTransition("active","accept"),{ok:true,state:"complete",replayed:false});
 for(const choice of ["hear","accept"] as const)assert.deepEqual(audienceTransition("complete",choice),{ok:true,state:"complete",replayed:true});
});
test("Elathra admission position matches authored scene and patrol radius",()=>{
 const scene=readFileSync(new URL("../../../scenes/world/six_zone_reverie/zone_01_royal_gardens.tscn",import.meta.url),"utf8");
 const match=scene.match(/\[node name="Elathra"[^\n]*\]\r?\nposition = Vector2\(([-\d.]+), ([-\d.]+)\)/);assert.ok(match);
 assert.equal(ELATHRA_POSITION.x,Number(match[1]));assert.equal(ELATHRA_POSITION.y,Number(match[2]));assert.ok(openingContains("story_royal_gardens",ELATHRA_POSITION));assert.equal(ELATHRA_POSITION.radius,164);
});
