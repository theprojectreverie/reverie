import test from "node:test";
import assert from "node:assert/strict";
import {buildBannerCatalog} from "../src/world/live-banners.js";
import {rollBanner,emptyPity} from "../src/world/summon.js";
test("Every Mythic pull is the featured Mythic on all six active banners",()=>{
 const catalog=buildBannerCatalog([]);
 assert.equal(Object.keys(catalog).length,6);
 for(const [id,b] of Object.entries(catalog)){
  assert.deepEqual(b.pool.mythic,b.featured,id);
  assert.equal(b.featured_rate,1);
  assert.equal(b.rates.mythic,.005);
  assert.equal(b.paid_rates?.mythic,.02);
  assert.equal(b.paid_rates?.legendary,.05);
  for(const paid of [undefined,0])for(let i=0;i<100;i++){
   let j=0;const r=rollBanner(b,emptyPity(),1,()=>j++===0?.999:(i+.5)/100,paid).results[0]!;
   assert.equal(r.character_id,b.featured[0],id);assert.equal(r.rarity,"mythic");assert.equal(r.featured,true);
  }
  assert.equal(rollBanner(b,emptyPity(),1,()=>0,99).results[0]?.character_id,b.featured[0]);
 }
});
