import test from "node:test";
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { validateMovementProposal, validateRegionBounds, validateRegionProposal } from "../src/world/movement.js";
import { REGION_BOUNDS, REGION_SPAWNS } from "../src/world/region-bounds.generated.js";

test("locks movement to the lobby's assigned region", () => {
  assert.equal(validateRegionProposal("castle_royal_gardens", "castle_royal_gardens"), true);
  assert.equal(validateRegionProposal("castle_royal_gardens", "greenward"), false);
  assert.equal(validateRegionProposal("", "greenward"), false);
});

test("loads every authored map_bounds entry from the canonical region manifest", () => {
  const regions = JSON.parse(readFileSync(new URL("../../../resources/data/regions.json", import.meta.url), "utf8"));
  const expeditions = JSON.parse(readFileSync(new URL("../../../resources/data/six_zone_expeditions.json", import.meta.url), "utf8"));
  const expected = Object.fromEntries(Object.entries(regions).filter(([, r]) => (r as any).map_bounds).map(([id, r]) => {
    const { min, max } = (r as any).map_bounds;
    return [id, { minX: min[0], minY: min[1], maxX: max[0], maxY: max[1] }];
  }));
  for (const [id, r] of Object.entries(expeditions)) {
    const [minX,minY,maxX,maxY] = (r as any).bounds;
    expected[id] = {minX,minY,maxX,maxY};
  }
  assert.deepEqual(REGION_BOUNDS, expected);
  assert.deepEqual(REGION_BOUNDS.castle_royal_gardens, { minX: -544, minY: -714, maxX: 3800, maxY: 7200 });
  assert.deepEqual(REGION_BOUNDS.gothic_castle_boss_zone, { minX: -400, minY: -320, maxX: 3200, maxY: 1600 });
});

test("enforces authored rectangular bounds for static regions without pretending to validate obstacles", () => {
  assert.equal(validateRegionBounds("castle_royal_gardens", { x: 640, y: 620.16 }), true);
  assert.equal(validateRegionBounds("castle_royal_gardens", { x: 3801, y: 620.16 }), false);
  assert.equal(validateRegionBounds("castle_royal_gardens", { x: 640, y: 7201 }), false);
  assert.equal(validateRegionBounds("gothic_castle_boss_zone", { x: 3200, y: 1600 }), true);
});

test("accepts initial position and normal movement", () => {
  assert.equal(validateMovementProposal(null, { x: 0, y: 0 }, 0).ok, true);
  assert.equal(validateMovementProposal({ x: 0, y: 0 }, { x: 35, y: 0 }, 0.1).ok, true);
});

test("rejects speed hacks and coordinates outside the world safety envelope", () => {
  assert.deepEqual(validateMovementProposal({ x: 0, y: 0 }, { x: 100, y: 0 }, 0.1), { ok: false, reason: "movement_speed" });
  assert.deepEqual(validateMovementProposal(null, { x: 100001, y: 0 }, 0.1), { ok: false, reason: "world_bounds" });
  assert.deepEqual(validateMovementProposal(null, { x: Number.NaN, y: 0 }, 0.1), { ok: false, reason: "invalid_position" });
});

test("clamps tiny elapsed intervals against division spikes", () => {
  assert.equal(validateMovementProposal({ x: 0, y: 0 }, { x: 40, y: 0 }, 0).ok, false);
});

test("generates authoritative spawn positions from canonical isometric region data", () => {
  assert.deepEqual(REGION_SPAWNS.greenward, { x: 0, y: 256 });
  assert.deepEqual(REGION_SPAWNS.castle_royal_gardens, { x: 640, y: 620.16 });
});

test("rejects lobby region IDs that are not present in canonical region content", () => {
  assert.equal(validateRegionProposal("not_a_region", "not_a_region"), false);
});
