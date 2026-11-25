# Willow Fields road-corner artwork QA — 2026-11-21

The playable zone_03_willow_fields.tscn currently contains 90 approved 64×32 full-ground transition tiles: 46 northwest/northeast grass-to-dirt turns and 44 southeast/southwest turns.

Production tile scenes:
- res://scenes/world/six_zone_reverie/terrain/willow_dirt_corners/transition_01_0.tscn
- res://scenes/world/six_zone_reverie/terrain/willow_dirt_corners/transition_02_0.tscn

These use art-defined grass/dirt boundaries and preserve the original hand-designed grass and soil textures. Whole ground tile instances are used; no stacked fringe overlay sprites.

The 394-piece full-perimeter treatment was rejected: obvious repeated grassy marks and unclean joins along long straight road sections. It remains isolated under qa/willow_artist_full_border_v2.tscn and is NOT deployed.

Gameplay QA: C:\Users\quoth\Downloads\willow_installed_native_details_gameplay.jpg
Comparison screenshot: C:\Users\quoth\Downloads\willow_artist_full_border_v2_center.jpg

Unresolved: seamless straight-edge tiles (all four directions), three-sided corners, river gridlines.
Acceptance criteria: no floating grass fragments, matching texture palette, correct native 64×32 tile alignment, playable camera screenshot, no new collisions or player scaling.

## Additional native corner pass — 2026-11-21
- Installed 38 additional painted 64x32 ground tile corners: 20 NE/SE and 18 NW/SW rotations, using the manually designed four-direction sprite reference.
- Total approved corner replacements now 128, all proper editor PackedScene instances on the original GroundTiles layer.
- Full 10,000 tile count preserved; all soil and approved mixed tiles form one connected road network; no collision nodes added.
- Existing original straight road edges remain visually angular and need their own approved native artwork; do not reinstate the rejected 394 overlay layer.

## Straight-road edge pass, 2026-11-21
- Added 263 narrow 64x32 complete straight-edge ground tile nodes in four isometric orientations (two variants each), retaining all original road artwork and the 128 approved corners.
- Corrected isometric tile direction mapping: row-1 is NE, col-1 is NW, row+1 SW, col+1 SE; rejected the reversed placement that produced green streaks.
- Native art from the original hand-painted grass and soil textures; no generic overlays, no collisions added.
- All 1395 road cells remain one connected group and total 10000 ground cells remain. Standalone Godot load test exit code 0.
- Still pending: true seamless irregular shoreline and removal of river diamond grid outlines.
