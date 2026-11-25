# Willow Fields River Surface QA — 2026-11-21

## Live scene changes
- Removed 10 visually detached riverbank Sprite2D overlays that appeared as little grassy islands on blue water.
- Retained original 421 WillowStream water Sprite2D tiles and the wooden bridge, waterfall, lily decorations, 10,000 ground cells, and 1,395 dirt-road cells.
- No new collisions. Kael and exploration camera unchanged.
- Standalone Godot headless launch test passed with exit code 0.

## Rejected tests (isolated QA only)
- Increasing water_tile.png sprite scale to 1.10–1.22 did not remove the dark diamond grid.
- Cropping and scaling the original Texture2D via Godot AtlasTexture also left visible grid lines.
- A single editor-authored Polygon2D river using original hand-painted pond water texture removed the grid but produced flat, blocky and brown-blue patches. Not installed.

## Next art requirements
- Proper hand-drawn seamless open-water artwork with no dark border on each diamond; four isometric shore sides and inside/outside corners.
- Native 64x32 isometric editor tiles/nodes, plus waterfall base and bridge approach bank pieces.
- Inspect at gameplay zoom and overview before installing.

QA screenshots in Downloads:
- willow_water_crop_2_QA.jpg
- willow_water_crop_4_QA.jpg
- willow_water_crop_6_QA.jpg
- willow_continuous_river_polygon_QA.jpg
- willow_live_river_bank_final_QA.jpg

## Approved water-node improvement, 2026-11-21
- The previous 421 framed blue diamond water Sprite2D instances were replaced 1:1 with 421 editable Godot Polygon2D water cells.
- Reuses existing hand-painted royal_garden_paths_water_atlas_32x32.png water imagery, correct direct atlas UVs (0,80; 16,64; 32,80; 16,96); no generated water art.
- Native 64x32 diamond locations and existing river shape unchanged; original nodes removed instead of hidden.
- Screenshot: C:\Users\quoth\Downloads\willow_live_river_bank_final_QA.jpg; dark diamond grid no longer prominent.
- No new collision nodes, Kael sprite/camera untouched; 10k ground, 1395 road, 421 water polygons, one connected river.
- Still to polish: natural shoreline transitions and bends, water texture variation near waterfall/bridge.
