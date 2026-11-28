import test from "node:test";
import assert from "node:assert/strict";
import {buildBannerCatalog,historicalBannerName} from "../src/world/live-banners.js";
test("Retired featured banners are absent from the active catalog, while history and regular pools remain",()=>{
 const catalog=buildBannerCatalog([]);
 assert.deepEqual(Object.keys(catalog).sort(),["crimson_fool","crimson_oath","eclipse_sovereign","flamebound_guardian","lily_of_shadows","moonlit_requiem"]);
 assert.equal(historicalBannerName("scarlet_requiem"),"Scarlet Requiem");
 assert.equal(historicalBannerName("crimson_covenant"),"Hollow Moon Overture");
 for(const b of Object.values(catalog)){
  assert.ok(b.pool.legendary.includes("nyx"));
  assert.ok(b.pool.legendary.includes("crimson_witch_legendary"));
 }
});
