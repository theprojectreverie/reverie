import test from "node:test";
import assert from "node:assert/strict";
import {banners,emptyPity,rollBanner} from "../src/world/summon.js";
test("Eclipse Sovereign features Mythic Ravienna",()=>{
 const b=banners.eclipse_sovereign!;
 assert.deepEqual(b.featured,["ravienna_mythic"]);
 assert.deepEqual(b.rates,banners.crimson_covenant!.rates);
 assert.deepEqual(b.cost,banners.crimson_covenant!.cost);
 assert.equal(rollBanner(b,{legendary:0,featured:159,epic_streak:0},1,()=>0).results[0]?.character_id,"ravienna_mythic");
 assert.equal(rollBanner(b,emptyPity(),1,()=>0,99).results[0]?.character_id,"ravienna_mythic");
});
