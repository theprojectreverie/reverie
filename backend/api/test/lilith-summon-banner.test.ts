import test from "node:test";
import assert from "node:assert/strict";
import {banners,emptyPity,rollBanner} from "../src/world/summon.js";
test("Moonlit Requiem features Mythic Lilith and preserves summon economics",()=>{
 const b=banners.moonlit_requiem!;
 assert.deepEqual(b.featured,["lilith_mythic"]);
 assert.deepEqual(b.rates,banners.crimson_oath!.rates);
 assert.deepEqual(b.cost,banners.crimson_oath!.cost);
 const pity=rollBanner(b,{legendary:0,featured:159,epic_streak:0},1,()=>0).results[0];
 assert.equal(pity?.character_id,"lilith_mythic");
 assert.equal(pity?.rarity,"mythic");
 assert.equal(pity?.featured,true);
 const paid=rollBanner(b,emptyPity(),1,()=>0,99).results[0];
 assert.equal(paid?.character_id,"lilith_mythic");
 assert.equal(paid?.paid_guaranteed,true);
});
