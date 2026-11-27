import test from "node:test";
import assert from "node:assert/strict";
import {banners,emptyPity,rollBanner} from "../src/world/summon.js";
import {buildBannerCatalog} from "../src/world/live-banners.js";
test("All five active banners feature Mythic characters and retain pity and paid guarantees",()=>{
 const catalog=buildBannerCatalog([]);
 assert.equal(Object.keys(catalog).length,5);
 for(const [id,b] of Object.entries(catalog)){
  assert.equal(b.featured.length,1,id);
  for(const roll of [rollBanner(b,{legendary:0,featured:159,epic_streak:0},1,()=>0).results[0],rollBanner(b,emptyPity(),1,()=>0,99).results[0]]){
   assert.equal(roll?.character_id,b.featured[0],id);
   assert.equal(roll?.rarity,"mythic",id);
   assert.equal(roll?.featured,true,id);
  }
  assert.equal(b.cost.single,120);assert.equal(b.cost.ten,1200);
 }
});
