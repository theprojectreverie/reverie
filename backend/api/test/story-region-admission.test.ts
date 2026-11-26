import test from "node:test";
import assert from "node:assert/strict";
import {eligibleOpeningRegions,openingRegionAllowed} from "../src/world/story-progression-proof.js";
test("isolated gardens require both verified victories and explicit pilot enablement",()=>{
 for(const tutorialComplete of [false,true])for(const geraldDefeated of [false,true])for(const enabled of [false,true]){
  const progress={tutorialComplete,geraldDefeated};
  assert.equal(openingRegionAllowed("story_royal_gardens",progress,enabled),tutorialComplete&&geraldDefeated&&enabled);
  assert.equal(eligibleOpeningRegions(progress,enabled).includes("story_royal_gardens"),tutorialComplete&&geraldDefeated&&enabled);
  assert.equal(openingRegionAllowed("story_village",progress,enabled),tutorialComplete);
  assert.equal(openingRegionAllowed("six_zone_royal_gardens",progress,enabled),true);
 }
});
