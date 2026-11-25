# Reverie — Act I World Structure

## Design reference
The user's two uploaded references define the visual target:
- The six-panel sheet defines each region's local composition.
- The wide panorama defines the continuous landform and winding route across the six regions.

## Master scene
`act1_world_structure.tscn`

The current scene is a node-based composition study for:
1. Royal Gardens
2. Royal Gate
3. Willow Fields
4. Elderwood Grove
5. Forsaken Ruins
6. Ruined Tower

It now uses one connected continent silhouette, overlapping biome ground regions, a winding road node, river/waterfall nodes, separate landmark scenes/sprites, environmental dressing, labels and entry markers. The Royal Gate landmark now instances the modular Royal Gate architecture and forecourt scene, rather than a single enlarged placeholder sprite. It does not use the panorama as a stretched world background.

## Important status
This is still a structural composition preview, not a finished playable world. The ground polygons and road are layout guides. They must be replaced by authored ground TileMapLayer data and placed modular path tiles before the area is considered production-ready.

The existing `castle_royal_gardens.tscn` remains the playable Royal Gardens zone. Its existing handcrafted scene composition is preserved.

## Production rules
- Build world zones from visible Godot scene nodes and TileMapLayer resources.
- Keep the existing PixelPen source projects and transparent PNG exports paired.
- Keep ground art aligned to the established 32×32 tile grid where applicable.
- Use separate reusable scenes for architecture, trees, bridges, water, props and collision.
- Keep the road continuous across zone boundaries.
- Add explicit collision boundaries and walkable bridges; no wall walking, clipping or flying.
- Do not use the panorama or six-panel sheet as playable world backgrounds.
- Do not use procedural/noise terrain, GDScript map generation, generic `_draw` renderers or runtime-generated visual maps.

## Next build order
1. Build the Royal Gardens zone from its existing playable scene and authored ground/path TileMapLayers.
2. Build Royal Gate as a complete node-based gatehouse and approach.
3. Build Willow Fields with a farmhouse, windmill, crop plots, fences and paths.
4. Build Elderwood Grove with layered forest, stream, waterfall and stone bridges.
5. Build Forsaken Ruins with broken architecture, dead/red foliage and traversable rubble.
6. Build Ruined Tower with elevated stone platforms, waterfalls, purple crystals and clear collision edges.
7. Connect the six authored zones into one continuous world scene and test player traversal across every join.
