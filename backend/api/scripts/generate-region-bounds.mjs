import { readFile, writeFile } from "node:fs/promises";
import { dirname, resolve } from "node:path";
import { fileURLToPath } from "node:url";

const scriptDir = dirname(fileURLToPath(import.meta.url));
const projectRoot = resolve(scriptDir, "../../..");
const sourcePath = resolve(projectRoot, "resources/data/regions.json");
const outputPath = resolve(scriptDir, "../src/world/region-bounds.generated.ts");
const regions = JSON.parse(await readFile(sourcePath, "utf8"));
const entries = Object.entries(regions).sort(([a], [b]) => a.localeCompare(b));
const bounds = {};
const spawns = {};
for (const [regionId, region] of entries) {
  if (!/^[a-z0-9_]{2,48}$/.test(regionId)) throw new Error(`Invalid region ID: ${regionId}`);
  if (region?.map_bounds) {
    const min = region.map_bounds.min;
    const max = region.map_bounds.max;
    if (!Array.isArray(min) || min.length !== 2 || !Array.isArray(max) || max.length !== 2 ||
        ![...min, ...max].every(Number.isFinite) || min[0] > max[0] || min[1] > max[1]) {
      throw new Error(`Invalid map_bounds for region: ${regionId}`);
    }
    bounds[regionId] = { minX: min[0], minY: min[1], maxX: max[0], maxY: max[1] };
  }
  const grid = Array.isArray(region?.spawn_grid) && region.spawn_grid.length === 2 &&
    region.spawn_grid.every(Number.isFinite) ? region.spawn_grid : [8, 8];
  // Match IsoMath.grid_to_world: 64x32 isometric tiles.
  spawns[regionId] = { x: (grid[0] - grid[1]) * 32, y: (grid[0] + grid[1]) * 16 };
}
const generated = `// Generated from resources/data/regions.json. Do not edit by hand.\nexport const REGION_BOUNDS: Readonly<Record<string, { minX: number; minY: number; maxX: number; maxY: number }>> = Object.freeze(${JSON.stringify(bounds, null, 2)});\nexport const REGION_SPAWNS: Readonly<Record<string, { x: number; y: number }>> = Object.freeze(${JSON.stringify(spawns, null, 2)});\n`;
await writeFile(outputPath, generated, "utf8");
console.log(`Generated ${Object.keys(bounds).length} region bound entries and ${Object.keys(spawns).length} spawn entries from resources/data/regions.json.`);
