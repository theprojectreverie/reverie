import test from "node:test";
import assert from "node:assert/strict";
import {buildBannerCatalog} from "../src/world/live-banners.js";
import {rollBanner,emptyPity,mythicRecipe} from "../src/world/summon.js";
test("Caelith is Legendary in the five current banners; Mythic reserved from off-banner draws",()=>{
 const catalog=buildBannerCatalog([]);
 assert.equal(Object.keys(catalog).length,5);
 for(const [id,b] of Object.entries(catalog)){
  assert.ok(b.pool.legendary.includes("caelith_legendary"),id);
  assert.ok(!b.pool.mythic.includes("caelith_mythic"),id);
  assert.equal(b.mythic_fusion?.caelith_legendary?.target,"caelith_mythic");
  assert.equal(b.rates.mythic,.005);
  assert.equal(b.paid_rates?.mythic,.02);
  for(const paid of [undefined,0]){
   for(let i=0;i<100;i++){
    let j=0;const r=rollBanner(b,emptyPity(),1,()=>j++===0?.999:(i+.5)/100,paid).results[0]!;
    assert.notEqual(r.character_id,"caelith_mythic",id);
   }
  }
 }
 assert.equal(mythicRecipe("caelith_legendary")?.cost,7);
});
