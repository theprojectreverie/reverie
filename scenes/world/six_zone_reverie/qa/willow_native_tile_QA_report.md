# Willow Fields — Native Tile Fit & Seam Review
Date: 2026-11-21
Project: six_zone_reverie / Zone 03

## Source
User download: C:\Users\quoth\Downloads\willow_fields_16_transparent_tile_candidates.zip
Number of candidate transparent PNGs: 16 (8 dirt-path, 8 water-bank).
Original dimensions: approximately 347–358 x 197–252 px.
Live map's ground cell dimensions: 64 x 32 px, isometric diamond.

## Test procedure
- Extracted PNGs and confirmed RGBA transparency.
- Fitted each to 64x32 for comparison using nearest-neighbor pixel sampling.
- Created an isolated editable Godot scene with every candidate on existing grass, dirt, or water neighbors.
- Launched and visually inspected the scene in Godot; kept the original world unchanged.
- QA screenshot: C:\Users\quoth\Downloads\willow_tile_fit_Godot_review.jpg
- Enlarged sample contact: C:\Users\quoth\Downloads\willow_16_native_64x32_QA.jpg

## Result: NOT APPROVED for placement
- Geometry: outer diamond corners are transparent, but several original sprites are not consistently registered; dirt_outer_corner_west has a 50 px top transparent margin in its source.
- Grass: bright yellow-green and dense turf differ from the existing muted blue-green grass.
- Dirt: bright tan/orange differs from the existing dark soil. A bright rectangle is obvious when joined to existing path tiles.
- Water: vivid cyan-white ripples differ from the existing muted dark blue. White seams and mismatched wave density are conspicuous.
- Detail at 64x32: some source detail collapses into tiny specks during required nonuniform reduction.
- A correctly sized sprite is not the same as a seamlessly tiling sprite.
- The 16 PNGs are usable as design references, NOT as a production-ready tileset.

## Target palette sampled from existing hand-designed textures
- Grass: mean #347650; median #327850.
- Soil: mean #604337; median #624438.
- Water: mean #335A85; median #355D8A.
These are reference averages, not a mandate to use flat fills. Match the original assets' light and shade range.

## Replacement art acceptance criteria
- Each tile is painted or otherwise designed at NATIVE 64x32 pixels from the outset; never merely shrink a 350x200 illustration.
- Fully transparent exterior outside the actual 64x32 diamond, with no alpha halos, hard background rectangles, or raised vertical walls.
- Same earth-brown, blue-green grass and muted blue water palette as the existing textures.
- Edge-to-edge seamless connections across all four diamond sides in a 3x3 neighboring-tile test.
- Separate inner and outer corners for dirt and river; distinctive shallow-water bank transitions; waterfall and bridge connections.
- Tested at both editor native scale and playable camera zoom.
- Only import into production scene when the actual Godot preview passes. Keep editable nodes and NO new collisions.

## Files
Godot QA scene: res://scenes/world/six_zone_reverie/qa/willow_tile_fit_comparison.tscn
Candidate assets: res://assets/world/six_zone_reverie/zone_03_willow_fields/qa_tile_candidates/
Original live zone: res://scenes/world/six_zone_reverie/zone_03_willow_fields.tscn (not modified in this QA pass).
