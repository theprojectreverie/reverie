import test from "node:test";
import assert from "node:assert/strict";
import {banners,rollBanner,emptyPity} from "../src/world/summon.js";
import {buildBannerCatalog} from "../src/world/live-banners.js";
test("All five banners have 2% paid Mythic and unchanged 0.5% crystal Mythic",()=>{
 for(const [id,b] of Object.entries(buildBannerCatalog([]))){
  assert.equal(b.rates.mythic,.005,id);
  assert.deepEqual(b.paid_rates,{...b.rates,common:.47,legendary:.05,mythic:.02},id);
  const draw=(r:number,paid?:number)=>rollBanner(b,emptyPity(),1,()=>r,paid).results[0]!;
  assert.equal(draw(.985).rarity,"legendary",id);
  assert.equal(draw(.985,0).rarity,"mythic",id);
  assert.equal(draw(.979,0).rarity,"legendary",id);
  assert.equal(draw(.94).rarity,"epic",id);
  assert.equal(draw(.94,0).rarity,"legendary",id);
  assert.equal(draw(.929,0).rarity,"epic",id);
  assert.equal(draw(.469,0).rarity,"common",id);
  assert.equal(draw(.49).rarity,"common",id);
  assert.equal(draw(.49,0).rarity,"rare",id);
  assert.equal(draw(0,99).character_id,b.featured[0],id);
  assert.equal(draw(0,99).paid_guaranteed,true,id);
  assert.equal(rollBanner(b,{legendary:0,featured:159,epic_streak:0},1,()=>0,0).results[0]?.character_id,b.featured[0],id);
 }
});
