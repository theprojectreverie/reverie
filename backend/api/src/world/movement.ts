import { REGION_BOUNDS, REGION_SPAWNS } from "./region-bounds.generated.js";

export type WorldPosition = { x: number; y: number };
export type MovementValidation =
  | { ok: true; speed: number }
  | { ok: false; reason: "invalid_position" | "world_bounds" | "region_bounds" | "movement_speed" };
export const WORLD_COORDINATE_LIMIT = 100000;
export const MAX_WORLD_MOVEMENT_SPEED = 650;

// Coarse envelopes are generated from the game’s canonical regions.json.
// They are not substitutes for obstacle collision.
export function validateRegionBounds(regionId: string, next: WorldPosition): boolean {
  const bounds = REGION_BOUNDS[regionId];
  if (!bounds) return true; // Regions without authored map_bounds retain the global safety envelope.
  return next.x >= bounds.minX && next.x <= bounds.maxX && next.y >= bounds.minY && next.y <= bounds.maxY;
}

export function validateRegionProposal(expectedRegionId: string, proposedRegionId: string): boolean {
  return Object.hasOwn(REGION_SPAWNS, expectedRegionId) && proposedRegionId === expectedRegionId;
}

export function validateMovementProposal(previous: WorldPosition | null, next: WorldPosition, elapsedSeconds: number, maxSpeed = MAX_WORLD_MOVEMENT_SPEED): MovementValidation {
  if (!Number.isFinite(next.x) || !Number.isFinite(next.y)) return { ok: false, reason: "invalid_position" };
  if (Math.abs(next.x) > WORLD_COORDINATE_LIMIT || Math.abs(next.y) > WORLD_COORDINATE_LIMIT) return { ok: false, reason: "world_bounds" };
  if (!previous) return { ok: true, speed: 0 };
  const elapsed = Math.max(Number.isFinite(elapsedSeconds) ? elapsedSeconds : 0, 0.05);
  const speed = Math.hypot(next.x - previous.x, next.y - previous.y) / elapsed;
  if (speed > maxSpeed) return { ok: false, reason: "movement_speed" };
  return { ok: true, speed };
}
