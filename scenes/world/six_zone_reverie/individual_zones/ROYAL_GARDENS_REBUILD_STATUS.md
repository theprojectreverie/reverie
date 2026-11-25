# Royal Gardens — Reference-Driven Rebuild Status

## Scope
Only the six_zone_reverie Royal Gardens original zone scene and its editor-authored supporting scenes were modified. The approved visual reference is the user-provided castle (upper-left), joined waterfall/pond (upper-middle), gazebo (upper-right), fountain plaza, gold-trimmed pink marble paths, and one lower-right exit. Work is NOT finished or reference-matched yet.

## Current playable scene
res://scenes/world/six_zone_reverie/individual_zones/zone_01_royal_gardens_standalone.tscn
Main terrain and art: res://scenes/world/six_zone_reverie/zone_01_royal_gardens.tscn

## Completed in this pass
- Built a broad editor-tile marble courtyard centered on the fountain.
- Rebuilt the castle-to-fountain corridor as a straight consistent-width tile path; fixed every hidden tile visibility mismatch found in live screenshot tests.
- Pink marble path network: 1,229 authored tile instances, one 4-neighbor connected component.
- Joined previously separated waterfall and pond visuals; pond natural feature scaled to 1.85; castle kept unchanged.
- Removed repeating grass lattice: existing artist grass_ground.png tiled by an editor-authored textured Polygon2D. Existing grass tiles were preserved but hidden; not procedural runtime drawing.
- Hid repetitive grass-flower tile scatter and placed nine V4 flowerbeds as reusable editor-authored Sprite2D nodes.
- Added a pair of small V4 exit banners flanking the SINGLE lower-right exit, visually off the walking path. Existing transfer trigger preserved.
- Prior resized furniture and sparse V4 props preserved; no collisions created or changed.
- Scene validates in headless Godot and was visually inspected in live GUI. Latest preview screenshot:
  C:\Users\quoth\Documents\Default Project\royal_gardens_rebuild_current_approved_for_next_pass.png

## Editor-authored supporting scenes
- res://scenes/world/six_zone_reverie/individual_zones/royal_gardens_v4_flowerbeds.tscn
- res://scenes/world/six_zone_reverie/individual_zones/royal_gardens_v4_exit_banners.tscn
- res://scenes/world/six_zone_reverie/individual_zones/royal_gardens_v4_sparse_placement.tscn
- res://scenes/world/six_zone_reverie/individual_zones/royal_gardens_layout_review.tscn (overview QA camera, separate from player camera)

## Unfinished: prioritize next
1. Gold-trimmed pink marble path BORDER, turning/intersection pieces and smooth stairs-to-road edge. Use proper hand-designed 64x32 editor tiles, not unaligned 112x112 V4 candidates.
2. Improve courtyard perimeter with a few structured planting beds, benches, and lanterns in the reference design, leaving ample negative space.
3. Polish landscaping by the waterfall basin; user reference pond is larger and naturally integrated.
4. Verify castle-side route and lower-right exit with in-game movement, keeping existing player-scale and camera exploration behavior.
5. Assess performance of retained hidden 8,800 ground node instances before pruning; keep a backup and do not remove world geometry silently.

## Constraints
Preserve the castle. Only hand-designed pixel art plus editor-authored Godot nodes. No generic runtime code-generated art. Do not alter existing solid collision geometry without a separate visual pass. Only one lower-right zone transfer exit. All changes must be verified visually, not only by a headless loading test.

## Follow-up pass — plaza lighting and editor cleanup (2026-11-21)
- Added `royal_gardens_v4_plaza_lanterns.tscn`: four small existing artist-drawn V4 royal lamp assets (Sprite2D, no collisions). Positions placed off the castle approach and fountain-plaza walking surface. Confirmed in the Godot overview.
- Reviewed original gold path border assets in `royal_gardens_tileset`: these are approximately 110 x 115 top-down-looking paving objects with opaque borders; **not** verified as 64 x 32 isometric tile-edge art. No forced road overlay added.
- Inspected hidden terrain node references: none detected. Removed 8,771 redundant hidden grass/flower PackedScene tile instances from `zone_01_royal_gardens.tscn`, keeping all 1,229 pink stone editor-authored tiles, the textured grass underlay, all scenery, the original castle and transfer setup. The full pre-cleanup scene is backed up as `zone_01_royal_gardens.tscn.before_hidden_grass_tile_prune`.
- Main Royal Gardens scene file reduced from 1,464,645 to 174,084 bytes (88.1%); this is a scene-file size reduction, not a measured FPS claim.
- Both the main zone and standalone zone load with zero reported Godot errors. Full-map overview after cleanup: `C:\Users\quoth\Documents\Default Project\royal_gardens_after_tile_cleanup.png`; no visible art loss in the screenshot.
- Prioritize properly artist-authored 64 x 32 gold-edged path tiles/corners before more road work. Do not reuse the incompatible 110 x 115 textures as ground tiles.
## Plaza proportion refinement (2026-11-21)
- Inspected existing gold-bordered paved imagery. The available artist-authored trim sprites are approximately 76–120 px square/rectangular, not 64×32 isometric terrain tiles; still no safe gold-border replacement approved. Do not scale/stretch them onto the road.
- Added a reusable editor-authored `royal_gardens_v4_plaza_planters.tscn` with 4 small pink rose planters around the plaza lawn perimeter and 1 small bench near the gazebo. Uses the already extracted V4 hand-designed PNGs. No collision changes.
- Increased planter scales to 1.12 after inspecting the first too-small arrangement, and shifted two southern planters nearer the courtyard. Result has useful breathing room while introducing the more formal planted lawn-edge look of the user's model.
- Confirmed the Zone 1 `ToNextZone` marker is at world (1576,2380), corresponding to ~tile (50,99), on the lower-right diamond edge. Its separate `Area2D` trigger has `RectangleShape2D` 112×96, collision mask 2, and targets `zone_02_royal_gate_standalone.tscn`. No new trigger, no collision edits.
- Live visual checked the updated Godot map: `C:\Users\quoth\Documents\Default Project\royal_gardens_plaza_final_qa.png`. Standalone and new planter scene load without Godot errors.
- Still not approved: smooth gold-bordered marble path edges/intersections and more deliberate upper garden natural landscaping. Keep original reference as target; do not call finished.

## Reference-composition improvement (2026-11-21, latest)
- Rebalanced key landmark scales toward the user-supplied reference (main castle stays unchanged): fountain 0.82 -> 1.23, gazebo 0.85 -> 1.22, northeastern white blossom replaced by an existing pink cherry blossom sprite at 1.64. Waterfall cliff 1.40 -> 1.73 and joined pond 2.20 -> 3.30, producing a larger centerpiece water garden. Confirmed in a full-map live Godot screenshot.
- Made `royal_gardens_lawn_paving_inlays.tscn`: 12 deliberately placed groups of four small hand-designed original paver tiles each. After overview QA increased each paver's scale to 1.45 and spacing to make the lawn detail readable. Each is an editor-authored Sprite2D, no procedural runtime drawing.
- Made `royal_gardens_lower_edge_garden.tscn`: nine small rose flowerbeds placed along the inside of the two lower diamond edges, deliberately leaving a gap at the ONLY lower-right exit; one pink cherry-blossom tree added near the lower point, entirely within map silhouette.
- Made `royal_gardens_waterfall_landscaping_v4.tscn`: nine small existing artist-made V4 flower and stone assets arranged to frame the waterfall basin. It does not obscure the water or block the connected pink-marble paths.
- Preserved the smaller bench furniture, the castle, the single Royal Gate transfer point and unchanged collision setup. Existing art asset images are used. No image was generated with runtime drawing scripts.
- Verified: 1,229 authored stone tiles still form ONE connected 4-neighbor network; main scene and standalone Zone 1 both load with zero Godot errors; single ToNextZone marker still at (1576,2380). Backups saved before each scene change.
- Latest Godot full-map screenshot on desktop: `C:\Users\quoth\Documents\Default Project\royal_gardens_pond_scale_qa.png`.
- STILL NOT FINISHED: accurate 64×32 pixel-art gold trimmed marble edges, refined intersection/corner variants, balanced ornamental lawn border hedges, and interactive walkability test require further work. Earlier sourced square paved-gold assets are not grid-compatible, so none were misused as tiles.

## Gold-crest inlays and southwest promenade follow-up (2026-11-21)
- Made `royal_gardens_marble_crest_inlays.tscn`: five individually hand-placed editor-authored Sprite2D ornaments using the existing original gold-pattern `path_stone_crest.png`. Kept them as subtle inlays, not a fabricated continuous gold road border. No generic code-generated imagery, no collisions.
- Corrected one four-paver lawn ornament previously outside the diamond, moving it fully within the map. All 48 lawn paver positions verified inside map bounds.
- Hid an unrelated freestanding rose arch formerly placed across the gazebo approach; retained the original node/asset for later reuse. The reference gazebo area reads cleaner.
- Added 80 individual existing 64×32 marble PackedScene tile instances to create the missing southwest courtyard promenade. It ends inside the zone, with no additional transfer point or collision area.
- Moved four existing flower/lantern objects to adjacent lawn positions after a proximity audit found their original placement overlapped the new promenade. Each shifted at least 6 tile-grid steps from its nearest new promenade tile. Backups saved.
- Verified the main map contains 1,309 connected stone tiles in one four-neighbor component; standalone Godot loads with zero errors; exactly one lower-right ToNextZone transfer marker preserved targeting Royal Gate.
- Full in-game QA screenshot: `C:\Users\quoth\Documents\Default Project\royal_gardens_southwest_path_clearance_qa.png`.
- Still not complete: artist-designed continuous gold-trimmed 64×32 border/turn tiles remain missing; source artwork suitable for this precision is not available in the current project. Full gameplay walkability and detailed path-corner QA still needed.

## Formal garden hedge design and 64x32 gold-paving visual QA (2026-11-21)
- Integrated `res://scenes/world/six_zone_reverie/individual_zones/royal_gardens_formal_hedge_islands.tscn` as `FormalHedgeIslands` in the main Royal Gardens scene: 9 scaled editor-authored Sprite2D hedge decorations from existing `15_flower_hedge.png` art, placed on lawns away from the road and arranged near the courtyard and lower garden. Backup `zone_01_royal_gardens.tscn.before_formal_hedge_islands`. QA screenshot `C:\Users\quoth\Documents\Default Project\royal_gardens_hedge_qa.png`.
- Discovered the approved 64x40 transparent Royal Gate tile set in the user's Downloads, archive `reverie_royal_gate_corners_edges_approved.zip`. Its manifest specifies 64x32 logical isometric footprint with 8px vertical ornament. Source artwork was copied for QA into `assets/environment/six_zone_reverie/royal_gardens_gold_paving_trial` (Royal Gate assets untouched).
- First isolated QA: `qa/royal_gardens_gold_edge_overview_trial.tscn` overlays 120 separate border sprites onto the existing pink garden stone tiles. FAIL: mixed pink base texture and bright grass/gold outer edges produced incompatible colors and seams. Screenshot `C:\Users\quoth\Documents\Default Project\royal_garden_gold_edge_trial_screenshot.png`.
- Second isolated QA: `qa/royal_gardens_full_gold_paving_overview.tscn` substitutes all 1,309 existing tiles in a **temporary trial zone** with consistent transparent 64x40 editor-prefab art, including boundary borders and corner types. FAIL visual QA: each border produces a scalloped outer edge at tile boundaries, and the brick/ornament patterns repeat conspicuously. The full map looks too lavender compared with the reference. Full screenshot `C:\Users\quoth\Documents\Default Project\royal_gardens_full_gold_paving_trial_screenshot.png`; close-up `C:\Users\quoth\Documents\Default Project\royal_gardens_full_gold_paving_closeup.png`.
- BOTH GOLD TRIALS REJECTED; neither is referenced by the playable Royal Gardens scene. Do not apply them without new user approval or substantial art correction. Their scene files remain under `scenes/world/six_zone_reverie/qa/` for comparison.
- Final safety check: original playable 1,309 hand-designed pink marble tiles still form one connected 4-neighbor network; 9 hedge nodes integrated; only one lower-right `ToNextZone` transfer remains, targeting Royal Gate. Both original and standalone Royal Gardens scenes load with zero reported Godot errors. No collisions changed.
- Next actual needed deliverable: purpose-designed artist-made 64x32 pink-marble EDGE STRIPS with continuous gold trim that visually tile straight and through concave/convex corners, with no protruding scallops or grassy perimeter. Validate in a separate zoomed Godot scene before using on the playable map.

## New pass — Royal Gardens exploration spawn and camera (2026-11-21)
- Updated the existing standalone zone controller only for fresh Zone 1 starts: instead of defaulting to the lower-right Royal Gate transfer marker, the playable character now spawns at world `(-832, 1216)`, on the pink-marble approach below the castle staircase. Existing inter-zone arrival marker behavior remains unchanged.
- Changed only Zone 1's exploration camera base zoom from 0.33 to a verified 0.52, showing the player and surrounding garden rather than the entire diamond or an extreme castle close-up. Other zones retain their previous camera settings.
- Live validated by launching the actual playable scene `zone_01_royal_gardens_standalone.tscn`. Player visibly appears on marble road beside the castle; scene doesn't open at the Royal Gate exit. QA screenshot: `C:\Users\quoth\Documents\Default Project\royal_gardens_exploration_camera_final_qa.png`. Backup of controller at `scripts/world/six_zone_reverie/standalone_zone_controller.gd.before_zone01_spawn_camera_refinement`.
- Current art budget for Pixel Engine is four credits, while the minimum exact-size artist-sprite generation costs six credits. No paid-generation job submitted and no placeholder/generated graphics introduced.
- The rejected 64x40 isometric gold-paving trials remain QA-only. The playable scene still retains the original 1,309 connected pink-stone tiles and single lower-right Royal Gate trigger; no collisions changed.
- Major unfinished art requirement: a seamless, hand-designed pink-marble edge/corner set with gold borders for 64x32 isometric ground tiles, approved by Godot zoomed-in visual QA before deployment.

## Marble notch cleanup (2026-11-21)
- Inspected all 1,309 authored 64x32 pink-marble road PackedScene tiles for spur tiles and 3-sided recessed grass gaps. Found zero dangling single-neighbor spurs and exactly two 3-sided recessed notches, at isometric grid (63,41) and (67,63).
- Filled the two notches with individual editor-authored `tile_p` PackedScene instances, leaving each pink marble asset unchanged and preserving the original scene nodes. New road count: 1,311; verified a single connected 4-neighbor road network.
- Backup: `scenes/world/six_zone_reverie/zone_01_royal_gardens.tscn.before_marble_notch_polish`.
- Confirmed one Royal Gate transfer marker remains; Zone 1 castle spawn and exploration zoom are unchanged; rejected gold-paving trials remain outside playable scene. Godot headless scene load: zero reported errors.
- Attempted a fresh GUI overview screenshot, but that process did not remain running in this pass. The two newly filled corners are structurally validated but not yet given a fresh visual-approval screenshot. Do NOT call the entire path visually approved.
- Next priority is a vetted seamless artist-designed 64x32 gold-trimmed pink marble edge/corner set, including separate straight-side, inside-corner, outside-corner and junction assets, tested at gameplay zoom. Avoid cropping or stretching the rejected Royal Gate paving into Royal Gardens.

## Rose-marble tone and focal-point balance (2026-11-21)
- Reopened the exact full-map Royal Gardens overview using Godot's `--scene` launch parameter, inspected the screenshot at `C:\Users\quoth\Documents\Default Project\royal_garden_true_overview_nov21.png`.
- Trialed and visually approved a Zone 1-only artist-asset color adjustment: editor-authored tile scene `royal_gardens_rosy_stone_64x32.tscn` references the original `garden_stone_path.png` and sets Sprite2D `modulate = Color(1,0.89,0.92,1)`. This is not regenerated art and changes no other zones.
- Adjusted central fountain scale from 1.23 to 1.53 and gazebo scale from 1.22 to 1.34 to better match the relative importance of the supplied visual reference, without making furniture larger.
- Tested in `qa/royal_gardens_rosy_marble_overview.tscn` first. QA screenshot `C:\Users\quoth\Documents\Default Project\royal_garden_rosy_marble_focal_trial.png`. Applied successful trial to `zone_01_royal_gardens.tscn` with backup `zone_01_royal_gardens.tscn.before_rosy_marble_focal_scaling`.
- Main and standalone scenes passed headless Godot scene loads with zero errors. Reopened playable Zone 1 with an explicit `--scene` and verified Kael still starts on the castle marble road. Playable screenshot `C:\Users\quoth\Documents\Default Project\royal_garden_rosy_marble_playable_qa.png`.
- Gold-trimmed pink-marble perimeter edges and inside/outside corner tiles still need vetted hand-designed sprites. The new tint and larger focal points are approved only as intermediate improvements, NOT final signoff of the garden.

## Pond composition and blossom-balance QA (2026-11-21)
- Inspected exact game overview and compared with user-approved reference. Reference pond is framed by pink-blossom trees on both sides; current garden only had the eastern pond cherry tree.
- Created separate Godot QA review scene `qa/royal_gardens_pond_left_blossom_preview.tscn` with one instance of the existing artist-drawn cherry-blossom texture at world (-200,825), scale 1.53. Full-map Godot preview screenshot: `C:\Users\quoth\Documents\Default Project\royal_garden_pond_left_blossom_trial.png`. The tree visually fills the empty castle-to-pond lawn without blocking the waterfall or marble road.
- Added one actual `Sprite2D` node `PondLeftBlossom` into the existing main-zone `RoyalGardenV3Decorations` editor layer using the same previously approved `garden_v3_3` texture. No new art generation or collision geometry.
- Saved main scene backup `zone_01_royal_gardens.tscn.before_pond_left_blossom` prior to change. Both original and standalone zone load with zero Godot errors.
- Verified the actual main-zone render after integration: `C:\Users\quoth\Documents\Default Project\royal_garden_pond_blossom_integrated_qa.png`. The composition is more faithful to the reference, with two blossom trees framing the basin.
- Reviewed existing evergreen alternatives: the available compatible pointed trees are potted; the unpotted evergreen uses a mismatched visual style. No unsuitable replacement placed.
- Final integrity: all 1,311 rose-marble tiles remain one connected network; unique lower-right transfer to Royal Gate preserved; all rejected gold-edge trial assets remain out of the playable map.
- Royal Gardens is NOT finished or reference-matched: true seamless gold-trimmed borders, refined intersections, and gameplay collision/walkability QA remain unfinished.

## Upper-garden scale correction (2026-11-21)
- In a separate QA preview, reduced only the two upper-garden potted cypress/topiary sprites (`TopiaryNorth` and `TopiaryEast`) from 1.70 to 1.22. This corrects excessive visual weight compared with the castle, gazebo and pond; the bottom/west cypress remain unchanged.
- QA preview file: `qa/royal_gardens_topiary_scale_overview.tscn`; live Godot screenshot: `C:\Users\quoth\Documents\Default Project\royal_garden_topiary_scale_qa.png`. Visual result approved as an intermediate proportion refinement.
- Applied in the main zone's original editor-authored `Sprite2D` nodes. Saved backup `zone_01_royal_gardens.tscn.before_upper_topiary_rescale`. Both main and standalone scenes passed Godot load checks with zero errors.
- Work is not final; the user's gold-bordered marble paths and clean turn/corner visual standard remain unfinished. Continue validating in-game screenshots before further acceptance claims.

## Walkway clearance audit and cleanup — 2026-11-22
- Ran a proximity sweep of all active custom Royal Gardens Sprite2D placement scenes against the 1,311-node authored pink-marble network. Filtered intentional marble inlays and identified three decoration anchors uncomfortably close to the main walkway.
- Moved `CourtyardSouthWestFlowers` to (-1450,2040), `CourtyardSouthEastFlowers` to (-100,2310), and `SmallRoyalBench` to (-1570,1920). Their marble-road grid clearances now measure 6.3, 6.4, and 10.1 tile steps, respectively, rather than about 3, 2.6 and 1.1 steps. Kept the approved texture and reduced sprite scales. Did not add any decorations or create collision.
- Reusable authored scenes changed: `royal_gardens_v4_plaza_planters.tscn` and `royal_gardens_v4_sparse_placement.tscn`. Backups: same names with `.before_courtyard_planter_clearance` and `.before_bench_walkway_clearance` suffixes.
- Godot headless loads of both supporting scenes and Zone 1 standalone passed with zero reported errors. Actual full-map Godot overview opened and inspected after the edits: `C:\Users\quoth\Documents\Default Project\royal_gardens_walkway_clearance_final_20261122.png`.
- Road integrity verified: exactly 1,311 tile instances in one 4-neighbor component. Only one Royal Gate transfer marker; castle, fountain, gazebo and other zones unaffected.
- Still awaiting purpose-designed seamless gold-border marble edge and corner assets; do not install the rejected gold trials or call the reference look finished.
