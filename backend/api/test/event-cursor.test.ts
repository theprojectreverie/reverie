import test from "node:test";
import assert from "node:assert/strict";
import {clampAcknowledgement,isReplayCursorValid} from "../src/world/event-cursor.js";
test("acknowledgements cannot advance beyond the latest server event",()=>assert.equal(clampAcknowledgement(4,999,8),8));
test("acknowledgements never move backwards",()=>assert.equal(clampAcknowledgement(7,2,9),7));
test("empty event streams only acknowledge zero",()=>assert.equal(clampAcknowledgement(0,4,0),0));
test("replay cursors reject future and unsafe integer positions",()=>{assert.equal(isReplayCursorValid(5,5),true);assert.equal(isReplayCursorValid(6,5),false);assert.equal(isReplayCursorValid(Number.MAX_SAFE_INTEGER+1,8),false);});
