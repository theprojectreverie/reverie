import test from "node:test";
import assert from "node:assert/strict";
import { PlayerRealtimeLimits } from "../src/world/realtime-limits.js";

test("limits concurrent connections across a player's lobbies", () => {
  const limits = new PlayerRealtimeLimits(2, 30);
  assert.equal(limits.open("player-a"), true);
  assert.equal(limits.open("player-a"), true);
  assert.equal(limits.open("player-a"), false);
  assert.equal(limits.open("player-b"), true);
  limits.close("player-a");
  assert.equal(limits.connectionCount("player-a"), 1);
  assert.equal(limits.open("player-a"), true);
});

test("shares the per-second message budget across all player sockets", () => {
  const limits = new PlayerRealtimeLimits(2, 2);
  assert.equal(limits.open("player-a"), true);
  assert.equal(limits.open("player-a"), true);
  assert.equal(limits.allowMessage("player-a", 1000), true);
  assert.equal(limits.allowMessage("player-a", 1100), true);
  assert.equal(limits.allowMessage("player-a", 1200), false);
  assert.equal(limits.allowMessage("player-a", 2000), true);
});

test("releases limiter state only after the final connection closes", () => {
  const limits = new PlayerRealtimeLimits(2, 1);
  limits.open("player-a");
  limits.open("player-a");
  assert.equal(limits.allowMessage("player-a", 100), true);
  limits.close("player-a");
  assert.equal(limits.allowMessage("player-a", 101), false);
  limits.close("player-a");
  assert.equal(limits.allowMessage("player-a", 102), true);
});

test("rejects invalid timestamps and constructor limits", () => {
  const limits = new PlayerRealtimeLimits();
  assert.equal(limits.allowMessage("player-a", Number.NaN), false);
  assert.throws(() => new PlayerRealtimeLimits(0, 30), RangeError);
  assert.throws(() => new PlayerRealtimeLimits(2, 0), RangeError);
});
