import test from "node:test";
import assert from "node:assert/strict";
import {banners,emptyPity,rollBanner} from "../src/world/summon.js";
test("Eclipse Sovereign rate-up and guarantees award Queen Ravienna",()=>{
 const b=banners.eclipse_sovereign!;
 assert.deepEqual(b.featured,["ravienna"]);
 assert.deepEqual(b.rates,banners.crimson_covenant!.rates);
 assert.deepEqual(b.cost,banners.crimson_covenant!.cost);
 assert.equal(rollBanner(b,emptyPity(),1,()=>0.97).results.length,1);
 const guaranteed=rollBanner(b,emptyPity(),10,()=>0,90).results[9];
 assert.equal(guaranteed?.character_id,"ravienna");assert.equal(guaranteed?.paid_guaranteed,true);
 const pity=rollBanner(b,{legendary:b.hard_pity-1,featured:b.featured_pity-1,epic_streak:0},1,()=>0).results[0];
 assert.equal(pity?.character_id,"ravienna");assert.equal(pity?.featured,true);
 const index=b.pool.mythic.indexOf("ravienna_mythic");assert.ok(index>=0);const draws=[0.999,(index+0.5)/b.pool.mythic.length];
 assert.equal(rollBanner(b,emptyPity(),1,()=>draws.shift()!).results[0]?.character_id,"ravienna_mythic");
});
