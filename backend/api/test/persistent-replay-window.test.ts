import test from "node:test";
import assert from "node:assert/strict";
import {canReplayFromCursor,hasContiguousEventSequences} from "../src/world/persistent-replay-window.js";

test("replay accepts a cursor immediately before the oldest retained event",()=>assert.equal(canReplayFromCursor(39,40,60,21),true));
test("replay rejects a cursor with a retention gap",()=>assert.equal(canReplayFromCursor(38,40,60,22),false));
test("replay rejects a future cursor",()=>assert.equal(canReplayFromCursor(61,40,60,0),false));
test("replay rejects windows larger than the bounded replay size",()=>assert.equal(canReplayFromCursor(0,1,250,201),false));
test("an empty event log only covers the current cursor",()=>{assert.equal(canReplayFromCursor(0,null,0,0),true);assert.equal(canReplayFromCursor(4,null,5,0),false);});
test("replay rejects unsafe and negative cursors",()=>{assert.equal(canReplayFromCursor(-1,1,4,2),false);assert.equal(canReplayFromCursor(Number.MAX_SAFE_INTEGER+1,1,4,2),false);});
test("replay rejects inconsistent retained sequence metadata",()=>{assert.equal(canReplayFromCursor(0,8,7,0),false);assert.equal(canReplayFromCursor(0,0,7,0),false);});
test("replay accepts a fully contiguous event sequence",()=>assert.equal(hasContiguousEventSequences(10,13,[11,12,13]),true));
test("replay detects a missing event inside the retained window",()=>assert.equal(hasContiguousEventSequences(10,14,[11,13,14]),false));
test("replay detects a missing final event",()=>assert.equal(hasContiguousEventSequences(10,13,[11,12]),false));
test("replay detects an empty but incomplete event window",()=>assert.equal(hasContiguousEventSequences(10,11,[]),false));
test("replay accepts an already-current cursor with no new events",()=>assert.equal(hasContiguousEventSequences(11,11,[]),true));
