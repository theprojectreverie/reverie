# Royal Gardens runtime QA — 2026-11-22

- Target: `individual_zones/zone_01_royal_gardens_standalone.tscn` in `six_zone_reverie`.
- Godot 4.7.2 headless standalone run with `--quit-after 5` returned **exit code 0**.
- Game data initialized; no fatal scene-load error reported.
- A Camera2D physics-interpolation process-mode warning remains. This warning was previously misread as an exit-code-1 failure due to PowerShell stderr handling.
- Standalone scene editor Camera2D zoom is now `Vector2(0.52, 0.52)` with a pre-edit backup; player camera controller independently applies 0.52 on fresh Zone 1 start.
- Player scene collision layer 2 and mask 1; castle uses `StaticBody2D` plus `CollisionPolygon2D`. No collision changes were made in this pass.
- Gameplay movement, camera jitter, castle collision geometry, and full map visual appearance **not** verified by the headless run.
- Existing rejected gold-border trials remain QA-only. Do not deploy without artist-made, visually vetted 64x32 isometric edge and corner art.

Next: visual gameplay camera and castle footprint check, then separately test continuous artist-made gold/pink marble border corners and intersections before touching the playable road network.

## Marble perimeter audit
- 1,311 distinct editor-authored rosy stone nodes, 0 duplicate grid coordinates.
- 462 exposed four-neighbor sides require edge/corner review.
- 0 isolated stone nodes.
- No tile artwork or collision changed during this audit.


## Castle and road connectivity audit
- Breadth-first search of 1,311 rosy-stone grid nodes found exactly **one connected component** of 1,311 nodes.
- Castle ground collision polygon has 15 vertices. Its transformed world-coordinate axis-aligned bounds are approximately x=-1668..-455, y=364..1122.
- Fresh Zone 1 player spawn (-832,1216) is outside that collision polygon by point-in-polygon testing.
- This is geometric static validation, not a visual collision approval or a movement playtest.


## Live physics-world QA (headless Godot)
- Instantiated the standalone scene, waited two physics frames and verified player exists at (-832,1216).
- Player Camera2D is current and has actual runtime zoom (0.52,0.52).
- PhysicsDirectSpaceState intersect_shape on the actual player collision capsule returned **0** layer-1 obstacle overlaps at spawn.
- Castle collision and zone-transfer Area2D both exist at runtime.
- All assertions passed; Godot process exited **0**. Temporary QA script removed afterward.
- Camera2D interpolation process warning persists; no live GUI visual/movement walkthrough performed.


## Camera processing warning fix
- Explicitly set Camera2D process_callback=0 (physics) on the reusable editor-authored player camera scene and the standalone ZoneCamera node, matching project-wide physics interpolation.
- Backed up both original .tscn files with suffix .before_physics_camera_process_20261122.
- Re-ran five-frame headless Royal Gardens startup: exit code **0**, no Camera2D interpolation warning and no errors.
- Camera smoothing remains disabled; player follow and actual graphical motion still need visual review.


## Expanded player spawn clearance test
- Headless Godot physics scene tested actual player capsule at spawn and at four adjacent offsets of 80 world units in cardinal directions.
- All five placements had **zero** obstacle overlaps. Castle StaticBody2D collision layer=1, transfer trigger monitoring=true.
- Player Camera2D is current with process_callback=0 (physics). Test exited 0 with no warnings.
- This is a five-point static physics test, not full path navigation or castle visual alignment validation.


## Royal Gardens exit trigger activation QA
- Spawned a real player in the standalone scene and moved its CharacterBody2D to the Zone 1 exit Area2D at (1576,2380).
- Godot physics body-entered signal fired: trigger.transferring=true; player is in the required player group, destination is the Zone 2 Royal Gate standalone scene.
- Full scene replacement was not verified because this isolated SceneTree harness instantiated Zone 1 as a child instead of setting current_scene.
- Camera interpolation warning unexpectedly appeared in this test harness, despite being absent in the prior --scene startup check; investigate in a proper scene launch.


## Verified full Zone 1 -> Zone 2 scene transfer (2026-11-23)
- Used SceneTree.change_scene_to_file to load the real Royal Gardens scene, then moved the live player into its exit Area2D and allowed physics frames to process.
- SceneTree.current_scene successfully changed from StandaloneZone01 to StandaloneZone02; Zone 2 player spawned at (0,900), and its Camera2D was current.
- First run exposed the previously unexplained Camera2D interpolation warning as Zone 2's editor ZoneCamera. Added process_callback=0 to that camera scene node, with backup .before_physics_camera_process_20261123.
- Repeated full transition: exit **0**, no warnings or errors. Temporary QA harness removed.
- Still requires graphical movement, castle collision alignment, and road-edge artwork approval.


## Live castle collision movement test (2026-11-23)
- Loaded Zone 1 as the current Godot scene and moved the real CharacterBody2D upward from (-832,1216) with velocity (0,-200) using move_and_slide over 180 physics frames.
- Castle StaticBody2D generated **305** slide-collision contacts; final player position (-517.37,896.29), showing the player sliding along the castle obstacle rather than phasing through it.
- Test exited 0 with no warnings/errors. Temporary test script removed.
- This validates collision behavior from one approach, **not** visual alignment or all castle faces.


## Zone 2 -> Zone 1 return transfer QA (2026-11-23)
- Loaded Royal Gate as current scene, placed the player inside the Return-to-Gardens Area2D, and allowed physics to process the scene change.
- Successfully loaded StandaloneZone01, returned player at (1576,2200), with player camera current.
- Waited 12 additional physics frames: remained in Zone 1, so no immediate bounce-back transfer.
- Godot exit 0 with no warnings or errors. Temporary harness removed.

## Marble path topology for hand-designed border artwork
- Existing 1,311 tile road has nine 4-neighbor patterns: NESW=994, NEW=61, ESW=56, NW=44, ES=43, SW=32, NES=31, NE=26, NSW=24.
- No dead-end or isolated tiles; 462 exposed grid-neighbor sides from prior perimeter audit.
- This is a placement specification for future compatible edge/corner artwork, **not** a deployed or visually approved asset set.


## Player-input and camera-follow QA (2026-11-23)
- Loaded the actual Zone 1 standalone scene, held the real Input action move_right for 75 physics frames, then released for 20 frames.
- Player input_enabled=true; player moved from (-832,1216) to (-541.332,1216), **290.668 world units**.
- Player Camera2D moved by the exact same 290.668 world units and retained its expected (0,-220) framing offset.
- Headless test exited 0 with no errors or warnings; temporary QA script removed.
- This verifies real locomotion input and camera tracking along one unobstructed approach, but not graphical presentation or complete route traversal.


## Castle collision visual overlay review (2026-11-23)
- Generated a diagnostic overlay (NOT a game asset) at individual_zones/royal_gardens_castle_collision_review.png by mapping the 15-point Godot CollisionPolygon2D through its parent transforms into the original 1536x1024 castle sprite pixel coordinates.
- Polygon traces the lower architectural mass and sits beneath the tallest roof/tower tops, consistent with a solid, non-walkable castle footprint. The overlay makes the collider's placement directly inspectable.
- Overlay is **review-only**; it has not been imported into a playable scene, and no gameplay collision geometry was changed.
- Exact visual fit and navigable approach still need approval in the Godot editor.


## Road-edge art candidate visual audit (2026-11-23)
- Created visual contact sheet at individual_zones/royal_gardens_existing_edge_candidates_review.png from 11 existing artist-authored path/corner textures, with their native sizes and transparency inspected.
- Existing active path is a 64x32 diamond with complete alpha silhouette. Eight legacy path variants are 32x32, including square cross/turn/curve pieces whose orientation and footprint do not match the active diamond grid.
- Two curated gold-trimmed paving corners are 76x116 and 84x92 L-shaped pieces, not seamless 64x32 diamond neighbors.
- **Decision:** reject direct deployment of these mismatched candidates; retain them as visual design references only. No code-generated substitute, scaling hack, or incompatible texture installed.
- A matching hand-designed 64x32 isometric border/corner set is still needed before replacing any tiles.

