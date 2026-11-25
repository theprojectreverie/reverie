import test from 'node:test';
import assert from 'node:assert/strict';
import {shouldSendWorldSyncHint} from '../src/world/persistent-sync-hint.js';

test('does not hint when client cursor is current',()=>assert.equal(shouldSendWorldSyncHint(12,12),false));
test('hints when client missed one or more committed events',()=>assert.equal(shouldSendWorldSyncHint(12,13),true));
test('hints when client cursor is zero and server has events',()=>assert.equal(shouldSendWorldSyncHint(0,4),true));
test('rejects negative and unsafe client cursors',()=>{assert.equal(shouldSendWorldSyncHint(-1,2),false);assert.equal(shouldSendWorldSyncHint(Number.MAX_SAFE_INTEGER+1,2),false);});
test('rejects invalid server cursors',()=>{assert.equal(shouldSendWorldSyncHint(1,-1),false);assert.equal(shouldSendWorldSyncHint(1,Number.MAX_SAFE_INTEGER+1),false);});
