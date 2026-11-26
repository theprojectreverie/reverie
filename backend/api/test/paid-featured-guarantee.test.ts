import test from "node:test";
import assert from "node:assert/strict";
import {banners,emptyPity,rollBanner,PAID_MILESTONE} from "../src/world/summon.js";

for(const [id,banner] of Object.entries(banners)){
 test(id+" paid milestone forces a real featured character across all roll types",()=>{
  for(const random of [0,0.2,0.55,0.85,0.97,0.999]){
   for(const progress of [90,91,95,99]){
    const {results}=rollBanner(banner,emptyPity(),10,()=>random,progress);
    const marked=results.filter(r=>r.paid_guaranteed);
    assert.equal(marked.length,1);
    const reward=marked[0]!;
    assert.equal(reward.index,PAID_MILESTONE-progress-1);
    assert.ok(banner.featured.includes(reward.character_id));
    assert.equal(reward.featured,true);
    assert.ok(["legendary","mythic"].includes(reward.rarity));
    assert.equal(reward.kind,undefined);
   }
  }
 });
 test(id+" ordinary rolls do not consume a paid guarantee and single pulls do",()=>{
  assert.ok(rollBanner(banner,emptyPity(),10,()=>0).results.every(r=>!r.paid_guaranteed));
  assert.ok(rollBanner(banner,emptyPity(),10,()=>0,89).results.every(r=>!r.paid_guaranteed));
  const result=rollBanner(banner,emptyPity(),1,()=>0.999,99);
  assert.ok(banner.featured.includes(result.results[0]!.character_id));
  assert.equal(result.results[0]!.paid_guaranteed,true);
  assert.deepEqual(result.pity,emptyPity());
 });
}
test("invalid featured pool fails closed rather than granting an off-banner paid reward",()=>{
 const banner={...Object.values(banners)[0]!,featured:["unknown_character"]};
 assert.throws(()=>rollBanner(banner,emptyPity(),1,()=>0,99),/invalid_paid_featured_pool/);
});
