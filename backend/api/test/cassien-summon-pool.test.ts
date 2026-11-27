import test from "node:test";
import assert from "node:assert/strict";
import {banners,emptyPity,rollBanner,upgradeCard,mythicRecipe} from "../src/world/summon.js";

test("Cassien Legendary remains available; Mythic only on Crimson Oath among active banners",()=>{
 for(const [id,banner] of Object.entries(banners)){
  for(const rarity of ["legendary","mythic"] as const){
   const target=`cassien_${rarity}`;
   if(!banner.retired&&rarity==="mythic"&&id!=="crimson_oath"){assert.ok(!banner.pool.mythic.includes(target),id);continue;}
   const isFeatured=banner.featured.includes(target);
   const others=banner.pool[rarity].filter(x=>banner.featured.includes(x)===isFeatured);
   const index=others.indexOf(target);
   assert.ok(index>=0,`${id}: ${target} missing from eligible pool`);
   const rank=["common","rare","epic","legendary","mythic"] as const;
   const lower=rank.slice(0,rank.indexOf(rarity)).reduce((n,r)=>n+banner.rates[r],0);
   const draws=[lower+banner.rates[rarity]/2,...(banner.pool[rarity].some(x=>banner.featured.includes(x))?[isFeatured?0:0.999]:[]),(index+0.5)/others.length];
   const outcome=rollBanner(banner,emptyPity(),1,()=>{assert.ok(draws.length);return draws.shift()!;});
   assert.equal(outcome.results[0]?.character_id,target,`${id}: ${rarity}`);
   assert.equal(outcome.results[0]?.kind,undefined);
  }
 }
 assert.equal(upgradeCard("upgrade_cassien_epic_v1")?.target,"cassien_legendary");
 assert.equal(mythicRecipe("cassien_legendary")?.target,"cassien_mythic");
});

test("Crimson Oath features exactly Mythic Cassien and honors paid guarantee",()=>{
 const b=banners.crimson_oath!;
 assert.deepEqual(b.featured,["cassien_mythic"]);
 assert.deepEqual(b.rates,banners.crimson_covenant!.rates);
 assert.deepEqual(b.cost,banners.crimson_covenant!.cost);
 const guaranteed=rollBanner(b,emptyPity(),10,()=>0,90).results[9];
 assert.equal(guaranteed?.character_id,"cassien_mythic");assert.equal(guaranteed?.rarity,"mythic");assert.equal(guaranteed?.paid_guaranteed,true);
 const pity=rollBanner(b,{legendary:0,featured:b.featured_pity-1,epic_streak:0},1,()=>0).results[0];
 assert.equal(pity?.character_id,"cassien_mythic");assert.equal(pity?.rarity,"mythic");assert.equal(pity?.featured,true);
 const hard=rollBanner(b,{legendary:b.hard_pity-1,featured:0,epic_streak:0},1,()=>0).results[0];
 assert.equal(hard?.rarity,"legendary");
});
