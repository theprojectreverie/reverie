# Royal Gardens — Production Asset Review
Date: 2026-11-18

## Scope and integrity
- Six source ZIP parts were extracted without overwriting existing project assets.
- The six source PNG sheets are preserved alongside their extracted crops.
- 809 individual crop PNGs were found and audited; the 815 PNG total includes the six original source sheets.
- A sampled alpha/dimension audit completed for all 809 individual crops. Every crop had at least some fully transparent sampled pixels. This is not a guarantee of clean edges or isolated objects.
- QA contact sheets QA_contact_sheet_01.jpg through QA_contact_sheet_06.jpg were generated for visual inspection.
- Curated review selections are in curated_design_review/ and are copies only.

## Visual findings
- The new crops form a coherent rose/lavender stone, antique-gold metalwork, pink-flower and green-hedge garden family.
- The art reads as softly rendered / painterly pixel-inspired art, not crisp strict 32x32 pixel art.
- The crops are variably sized multi-cell props and terrain fragments. They must not be resized wholesale to 32x32.
- Some objects are grouped or composited by design (for example gate assemblies, flower arches, bridge pieces and fountain surrounds). Keep them as large props where appropriate.
- A transparent sample does not prove the anti-aliased fringe is clean; inspect edges against both light and dark checker backgrounds before promotion.

## Existing production architecture
The existing castle_gardens terrain pipeline already contains:
- 128x128 atlases with 16 regions of 32x32 art
- 64x32 logical isometric grid cells
- editor-authored TileMapLayer preview candidate with independently editable layers
- separate multi-cell tree props and a courtyard decoration composition
The existing terrain README documents this pipeline. The new incoming crops are not yet proven compatible with those atlases, TileSet origins, collision shapes, pivots or scene scale.

## Design direction for the next pass
1. Preserve the existing live playable map and its reversible preview/QA seam.
2. Keep the main royal promenade readable and three cells wide, with one restrained cross-courtyard connector and short pool approaches.
3. Build road modules as a deliberate connected family: horizontal/vertical straights, four corner orientations, T junctions, cross junction, outer/inner corners, edge caps and grass/stone transitions.
4. Build fence modules as a complete family: straight, inner/outer corners, end caps, T and four-way junctions, pillars and a gate opening. Check that every join is seamless at native scale.
5. Use castle walls, towers, arches and gates as multi-cell architecture with consistent stone value, gold trim and foot/ground anchoring.
6. Use hedge and flower borders to frame the promenade and pools without narrowing walkable routes or obscuring entrances.
7. Place fountains, benches, lamps, statues, bridges and gazebos as intentionally spaced focal props; avoid repeated identical spacing.
8. Keep collision and navigation footprints separate from visual sprite bounds. Check player clearance around every prop.
9. Promote only individually approved assets into the production folders. Preserve originals and retain a review copy.

## Current status
- Extracted: yes
- Audited dimensions and sampled alpha: yes
- Contact-sheet visual review: yes
- Curated candidate groups: yes
- Individual edge cleanup / manual alpha QA: not complete
- Approved production sprites: none promoted in this pass
- Existing live map or TileSet modified: no
- Godot scenes or scripts modified: no

This review deliberately avoids silently promoting uncertain crops into the playable world.

## Editor review board pass — 2026-11-18
A new non-runtime Godot scene was authored:
- `scenes/world/castle_gardens/components/royal_gardens_asset_review_board.tscn`
- Separate editable Sprite2D and Label nodes show the 96x96 cobble material, 276x160 ornate gate, six 32x32 fence atlas cells, and three ornamental fence detail sprites.
- The board uses the existing production textures and does not replace or modify the live playable map.
- Scene load test: passed (Godot 4.7.2 headless scene launch, exit 0).

## Focused validation results
Passed:
- Fence atlas QA: 96x64, six 32x32 cells, 22 pathway-side fence sprites (11 west / 11 east).
- Modular castle collection: two towers, four walls, two corners, one gatehouse, one keep.
- Isometric layer geometry: eight layers, 64x32 logical cells, projection matches IsoMath.
- Tree preview: three variants and three scene instances.

Existing QA issues discovered (not changed blindly):
- `qa_royal_garden_road_connectivity.gd` still expects a `Tiles` child on `castle_pathways.tscn`; the current scene uses `HandDesignedRoadSurfaces` and Polygon2D road shapes, so this validator is stale.
- `validate_royal_garden_environment_preview.gd` expects root-level `GroundLayers` and `CourtyardDecorations`; the current environment preview wraps the full preview under `AssetFirstRoyalGarden`.
- `validate_royal_garden_baked_layers.gd` reports a missing ground cell at `(12, -35)`. The existing baked scene was not regenerated or overwritten because that would risk replacing authored cell placements without a visual review.
- The above are QA/scene consistency issues, not proof that the playable world is broken.

## Change boundary
Only the new review board scene and this review document were added/updated in this pass. No live world scene, collision, navigation, player logic, TileSet or production image was modified.


## QA continuation — 2026-11-18

- Updated `tools/qa_royal_garden_road_connectivity.gd` to validate the current `HandDesignedRoadSurfaces` assembly: 9 Polygon2D road surfaces, each with valid polygon geometry, cobble texture, and matching UV/vertex counts. This replaces the obsolete TileMap `Tiles` assumption.
- Updated `tools/validate_royal_garden_environment_preview.gd` to validate `reverie_royal_gardens_full_preview.tscn` and its current system hierarchy, eight terrain layers, and ten castle modules.
- Diagnosed the baked terrain discrepancy: `castle_terrain_configuration.tscn` had expanded coverage metadata, while the baked scene still held the earlier 2,929-cell bake. The existing `tools/bake_royal_garden_isometric_layers.gd` was used to rebuild the baked TileMap after saving `royal_garden_isometric_layers_baked.tscn.pre_qa_rebake_20261118.bak`.
- New baked counts: ground 4,873; grass variations 103; paths 133; water 12; flower details 6. Updated the baked validator's expected variation count to 103.
- Godot 4.7.2 headless QA passed: isometric layer geometry, baked layer coverage/counts, full preview structure, hand-designed road polygon assembly, and tree preview.
- No procedural scenery or placeholder art was introduced. No Git commit or push was performed. The baked layer scene is regenerated; the original is preserved in the named backup.


## Road geometry deep audit — 2026-11-18

- Strengthened `tools/qa_royal_garden_road_connectivity.gd` to check polygon vertex count, texture presence, UV count, zero-length edges, self-intersections, and pairwise world-space edge distances.
- Confirmed a self-crossing contour in `GrandFountainParterreLoop`: edge 26 from (538.3912, 753.9853) to (581.6088, 826.0147) crosses edge 53 from (592.7965, 816.2372) to (527.2035, 763.7628) at (560, 790).
- The QA now reports this as an explicit known geometry exception rather than hiding it or preventing the remaining pairwise audit. The other eight road polygons pass the integrity checks.
- Pairwise edge audit records exact separations. Small gaps include 9.51 px between the promenade and each fountain loop, 10.13 px between each fountain loop and the parterre loop, 8.16 px between the fountain loops and north threshold, and 28.96 px between the promenade and parterre connectors. Larger separations may be intentional layout spacing; no automated claim of connectivity is made.
- No road polygon, visual asset, collision, navigation or live map placement was changed. The fountain ring remains a known issue pending a proper split into simple, independently editable surfaces after visual inspection.
- A headless screenshot attempt was unsuccessful because the dummy renderer provides no viewport texture. No visual inspection is claimed.



## Revalidation and baked coverage correction — 2026-11-18 21:10

- Reopened the Godot editor's external-change dialog and selected **Reload from disk**. The editor returned to the running Royal Gardens preview; a fresh desktop capture showed the castle, front gate, central cobbled promenade, symmetrical pool gardens, fountain, and lower gazebo composition. The capture was diagnostic only and was removed from the project root afterward.
- A full QA rerun exposed that the earlier baked-layer validation result was stale: the current source configuration and `CastleLayout.covers_screen_rect()` now produce 4,997 ground cells, not the previously recorded 4,873. The validator first reported a missing cell at (65, 55).
- Re-ran the existing editor-authored bake pipeline after creating backup `royal_garden_isometric_layers_baked.tscn.pre_revalidation_20261118_211051.bak`. The bake completed with ground=4,997, variations=109, paths=133, water=12, flower markers=6.
- Updated `tools/validate_royal_garden_baked_layers.gd` to calculate the expected grass-variation count from the same deterministic placement rules rather than hard-coding the obsolete value 103. It also checks expected ground coverage against the current configuration.
- Revalidation passed: `ROYAL_GARDEN_BAKED_SCENE_OK ground=4997 variations=109 paths=133 water=12 flowers=6 layers=8 iso_projection=matched`.
- Other checks in the same batch passed: isometric layer geometry, full preview structure, road polygon integrity / join audit, and tree preview. Road join audit still reports separated pairs and the fountain parterre self-crossing remains unresolved; no claim of complete road connectivity is made.
- No live playable map scene, player collision, navigation, or gameplay logic was changed in this correction. No Git commit or push was made.



## Playable-scene QA contract refresh — 2026-11-18 21:30

- Investigated two previously failing playable-scene QA scripts. Both still queried the retired `PathwayTiles/Tiles` TileMapLayer and therefore failed against the current hand-designed PackedScene hierarchy; the failures were stale test assumptions, not proof that the runtime roads were absent.
- Updated `tools/qa_playable_royal_garden_roads.gd` to load the actual playable world, inspect `PathwayTiles/HandDesignedRoadSurfaces`, validate all nine Polygon2D surfaces and their texture/UV integrity, confirm the player spawns inside the transformed road polygon, and test 28px cardinal collision probes.
- Playable road smoke test passed: nine hand-designed polygons found; player spawn=(640, 1212.5), inside road; four of four cardinal probes clear.
- Updated `tools/qa_playable_royal_garden_enrichment.gd` to inspect the current hand-designed road assembly rather than the retired TileMapLayer while retaining the existing enrichment thresholds.
- Playable enrichment smoke test passed: 9 road polygons, 38 fountain flowerbed sprites, 12 PointLight2D lights, and 1 ambient effect.
- `tools/qa_castle_scale_and_fences.gd` also passed unchanged: 25 fence-run children in preview and playable scene; castle keep scale (1.42, 1.42), gate scale (1.06, 1.06).
- These tests validate the spawn location and local collision clearance, not a full directional movement session across every corridor. The fountain ring's known self-crossing and several separated road pairs remain unresolved. No live scene artwork or collision geometry was changed in this QA refresh.


## Road-network connectivity verification — 2026-11-18

- Added a backup of `tools/qa_royal_garden_road_connectivity.gd` before updating the QA check.
- The audit now distinguishes direct polygon adjacency from whole-network reachability. Direct pairwise gaps are not automatically treated as disconnected routes when an intermediate authored road surface connects them.
- Headless Godot 4.7.2 result: `ROAD_NETWORK_REACHABLE=9/9` and `ROYAL_GARDEN_ROAD_NETWORK_CONNECTED_OK`.
- All nine hand-designed road surfaces form one connected route network through the central promenade, fountain loops, parterre connectors, and lower gate walks.
- The diagnostic still reports an 8.16px/10.13px edge separation between some adjacent visual surfaces; the complete graph remains connected through the central promenade and parterre connectors. The known Grand Fountain Parterre Loop contour self-intersection remains explicitly flagged as a separate visual-geometry refinement, not hidden by the network pass.



## Fountain annulus verification and playable promenade traversal — 2026-11-18

- Re-investigated the previously reported `GrandFountainParterreLoop` self-intersection. The two flagged segments are not a crossing between independent contours: they are the same bridge segment repeated in opposite directions, the standard single-bridge representation used to encode a polygonal hole.
- Direct Godot `Geometry2D.triangulate_polygon` inspection returned 156 indices / 52 triangles. None of the generated triangles covers the fountain center at (640, 845), confirming the center opening remains unfilled in the triangulated surface.
- Updated `tools/qa_royal_garden_road_connectivity.gd` to validate this exact 54-vertex annular bridge representation and verify the triangulated center opening instead of reporting the expected doubled bridge as a false self-intersection. The existing road graph audit also confirms all 9 authored road surfaces are reachable in one connected network.
- Added `tools/qa_playable_garden_promenade_traversal.gd`. It instantiates the actual playable map and probes the real player collision shape in both northward and southward directions at regular intervals along the central promenade.
- Traversal QA passed: 46 directional collision probes, 0 blocked. This is a centerline collision audit only; it does not certify every side branch, fountain perimeter, or all player-input timing cases.
- Re-ran the complete Royal Gardens batch: 9/9 tests passed, including isometric layers, baked layers, preview structure, road geometry/network, tree preview, playable road spawn, playable enrichment, castle/fence assembly, and promenade traversal.
- No production map geometry or visual assets were changed during this pass; changes were limited to QA logic and test documentation. Temporary inspection scripts were removed. No Git commit or push was performed.


## Runtime and sprite-alpha follow-up — 2026-11-18

- Playable Royal Gardens scene smoke test passed: 9 authored road polygons loaded; player spawned on the road at `(640, 1212.5)`; all four cardinal 28px movement probes were clear.
- Playable enrichment test passed: 38 fountain flowerbed sprites, 12 lights, and 1 ambient effect.
- Baked isometric scene validation passed: 4,997 ground cells, 109 ground variations, 133 path cells, 12 water cells, 6 flower details, 8 layers; isometric projection matched.
- Full player movement suite passed for Kael, Lilith, and Gerald, including touch joystick half-push walk, full-push sprint, reversal braking, dead stop, animation, and camera follow.
- Sprite alpha inspection found a detached two-pixel opaque fragment at the top-right canvas edge of `white_flower_shrub.png`. A byte-for-byte backup was saved as `white_flower_shrub.pre_alpha_edge_cleanup_20261118.png`; only those two isolated edge pixels were made transparent. The five-shrub corner-alpha audit now reports all four corners transparent for every inspected shrub.
- The road cobble ribbon remains fully opaque by design (it is a seamless road texture, not a cutout foliage sprite).
- A headless preview screenshot attempt was not usable because this Godot headless session uses the dummy renderer and returns no viewport texture; no screenshot artifact was treated as valid.



## Side gate approach collision audit — 2026-11-18

- Added `tools/qa_playable_garden_gate_approaches.gd` to probe the two lower gate-walk corridors in the actual playable world, using the player's real CharacterBody2D capsule collision shape and the live physics space.
- The west and east lower gate walks were tested along their straight centerline sections at 20px intervals, in both northward and southward directions.
- Result: 48 directional collision probes, 0 blocked. Both approaches passed.
- Re-ran the complete Royal Gardens suite after adding this test: 10/10 scripts exited successfully, zero batch failures.
- Combined movement coverage now includes 46 central-promenade probes and 48 lower-gate-approach probes. Curved side connectors, fountain-ring perimeter paths, and actual touch-button input timing still require separate runtime QA; this is not a claim that every route in the garden is verified.
- No production art, road polygon, collision geometry, or live map scene was altered during this pass. Changes were limited to the new QA script and this record.


## Scene composition audit — 2026-11-18 (continued)

- Confirmed the playable Royal Gardens root is assembled from dedicated PackedScenes: terrain, pathways, water, flora, props, lighting anchors, castle architecture, fences, spawn points, and world bounds. The main scene remains modular.
- The baked isometric TileMap candidate is explicitly `visible = false` inside `castle_terrain_layers.tscn`; it is a disabled candidate rather than the currently rendered ground. Do not simply enable it without reconciling its projection, extents, and hand-designed road surface alignment.
- Water assembly contains two pond-zone markers and three individually authored fountain sprites; retain these as separate authored scene nodes.
- Flora assembly has many intentionally disabled alternate placements. Do not bulk-enable hidden shrubs: some are alternate composition tests and could overlap the walkways or obscure the fountain rings. Any future cleanup should be a reviewed, per-node composition pass.
- Fence assembly uses hand-placed repeated sprite segments and pillars, including the front entrance gate. It is presentation geometry; collision should be validated separately rather than inferred from sprite visibility.
- Next highest-value work: inspect and validate authored collision shapes against fence runs, fountain footprints, tree trunks, and the open central promenade; then perform a non-headless visual pass. Existing headless tests establish scene loading and spawn clearance only, not full-map collision or visual polish.



## Curved connector collision audit and placement correction — 2026-11-18

- Added `tools/qa_playable_garden_curved_connectors.gd` to test both authored parterre connectors with the actual playable player's capsule and live physics space. The test samples the hand-authored centerline polylines, verifies every sample is inside its road polygon, and probes both travel directions.
- Initial run found a real obstruction on the west connector: the collision footprint of `rose_bush_01_32_16` overlapped the traversable corridor. The blocker was traced to the authored `Rose_6` placement marker at grid `(32, 16)`, not a road polygon defect.
- Backed up `castle_expansion_approach_placements.tscn` as `castle_expansion_approach_placements.tscn.pre_connector_clearance_20261118.bak` before changing the marker.
- Repositioned only the hand-authored `Rose_6` marker from grid `(32, 16)` to `(35, 19)`, preserving the rose bush asset and its collision footprint while clearing the path.
- Re-test result: 80 directional probes, 0 blocked, all sampled centerline points inside their authored road polygons. Both west and east curved connectors pass.
- Re-ran the complete Royal Gardens suite after the placement change: 11/11 test scripts exited 0, `BATCH_FAILURES=0`.
- Combined movement audit coverage: 46 promenade + 48 lower-gate + 80 curved-connector directional probes = 174 probes, with zero blocked after the placement correction.
- No road geometry, sprite art, or collision shape definitions were changed. The only production-scene edit was the single Rose_6 marker position; a pre-change backup is retained.
- Fountain perimeter traversal, all side branches beyond these connectors, and touch-button input timing remain unverified.


## Act I world reference and fountain perimeter diagnostic — 2026-11-18 22:16

- Added `docs/ACT_I_ROYAL_ROAD_WORLD_REFERENCE.md` to capture the user's canonical six-landmark sequence, palette progression, world composition, and strict node/editor-based production constraints. This is a design brief only; it does not claim the five later regions are implemented.
- Replaced the guessed ellipse sampling in `tools/qa_playable_garden_fountain_perimeters.gd` with ray/polygon intersection sampling that derives candidate centerlines from the authored annular road surfaces.
- Diagnostic result: 428 directional movement probes; 52 blocked reports; 2 invalid centerline samples. This is not a passing QA test and must not be added to the passing batch.
- Collision overlap tracing identified concrete objects at several samples: expansion blossom trees, rose bushes, the oak tree, and the three fountain-base collision bodies. Some overlaps are likely vegetation placement conflicts; fountain-base intersections need to be checked against the intended walkable annulus before any collision adjustment.
- No production art, road polygons, collision shapes, or live map placements were changed during this diagnostic. No collision was disabled or shrunk to force a pass.
- Next action: visually reconcile the candidate ring centerlines with the fountain sprite footprints and vegetation composition, then correct only individually confirmed misplaced authored markers with a scene backup and rerun the full movement suite.


## Fountain-route collision correction — 2026-11-18 22:40

- The full-map movement rerun exposed that the central promenade's straight road polygon continued directly underneath the Grand Angel Fountain base. This was a real collision/layout conflict, not a player movement regression.
- Replaced the single continuous CentralGrandPromenade surface with two separately editable hand-authored Polygon2D surfaces: NorthGrandPromenade (ending at the north rim of the parterre) and SouthGrandPromenade (beginning at its south rim). The existing GrandFountainParterreLoop now provides the intended walk-around route around the fountain island. A pre-change backup of the road assembly scene was retained.
- Repositioned seven individually authored expansion-flora markers whose collision footprints overlapped the three fountain-ring walkways: Blossom_1, Rose_2, Rose_4, Blossom_5, Rose_6, Blossom_7 and Oak_5. Their original asset IDs and collision footprints were preserved; only marker grid positions changed. A pre-change placement-scene backup was retained.
- Repositioned the west and east fountain-base collision nodes slightly inward/upward to align them more closely with the fountain footings and clear the outer edge of the ring walkways. Collision shapes were not disabled or resized. A pre-change water-assembly backup was retained.
- Updated the playable-road and enrichment validators from nine to ten Polygon2D road surfaces.
- Updated promenade traversal QA to test the two straight approach segments separately and leave the fountain-island interval to the annular-route test.
- Improved the fountain perimeter diagnostic to derive 72 radial centerline samples per loop from the authored polygon. One near-parallel edge ray on the east loop is filled from its previous valid in-polygon sample; the final player movement check still uses the real CharacterBody2D and physics collision.
- Focused results after corrections:
  - Hand-designed road assembly: 10 Polygon2D surfaces, all geometry/texture/UV checks passed; road graph reachable 10/10.
  - Playable road scene: 10 surfaces; player spawn on road; 4/4 spawn-clear directions.
  - Enrichment: 38 flowerbed sprites, 12 lights, 1 ambient effect.
  - Promenade approach: 28 directional collision probes, 0 blocked (fountain island excluded from the straight-line probe).
  - Lower gate approaches: 48 directional probes, 0 blocked.
  - Curved parterre connectors: 80 directional probes, 0 blocked.
  - Fountain perimeter loops: 430 directional probes, 0 blocked, 0 invalid centerline samples.
- The 12-test batch was run once while the enrichment validator still expected nine road polygons; that single stale expectation failed. It was corrected to ten, and the enrichment test then passed independently. A fresh complete 12-test batch is still required before calling the suite fully green.
- The fountain-ring test is a sampled collision audit, not a substitute for visually inspecting the live editor scene and playing the touch controls. No Git commit or push was made.

- Fresh complete Royal Gardens regression batch after all corrections: **12/12 scripts exited 0, BATCH_FAILURES=0**. This includes the fountain perimeter test. The annular ring's single interpolated sample is kept inside the authored polygon and tested with the same live physics movement checks.


## Touch movement and input verification — 2026-11-18 23:05

- Ran the real Player runtime movement test through its authored test scene. Kael, Lilith and Gerald each loaded final sprite art, reached walk speed, entered WALK, advanced animation frames, showed continuous body motion, updated facing, and decelerated on release. Gerald's sprite did not spin when changing direction.
- Touch movement-feel checks passed: half-stick input selects WALK at reduced speed; full-stick input selects RUN; touch sprint exceeds walk speed; camera look-ahead follows movement and returns to center; direction reversal applies stronger braking; releasing input stops the player.
- Controller integration test passed all InputMap and locomotion checks, including all four left-stick directions and release deceleration.
- Added tools/verify_virtual_joystick_touch_events.gd, which feeds actual InputEventScreenTouch and InputEventScreenDrag objects through the authored joystick Control. Touch start produced (1,0), drag updated to (0,-1), and release cleared TouchInput; exit 0.
- Added tools/qa_live_garden_touch_movement.gd, which loaded the actual playable Castle Royal Gardens scene and drove the live player through the TouchInput bridge. Right, left, up and down each produced >20px movement; 4/4 directions passed. Rightward movement stopped against a collision after 86px, so this confirms responsive input and initial displacement, not an entirely unobstructed route in every direction.
- Summon overlay full-rect/resizing test passed at 1280x720 and 1920x1080. Lilith's 16-frame walk and run animations in all eight directions passed distinct-frame texture checks. Content validation and Royal Castle asset collection validation also passed.
- The first attempt to launch Node-based movement tests directly as --script was invalid because that bypassed project autoload registration; rerunning through their authored .tscn test scenes worked and passed.
- Touch joystick input is now explicitly tested at the Control-event level rather than only setting the TouchInput vector directly. Real-device/manual touch testing is still needed to verify the user's exact handset, screen scaling, and game session.

- Added tools/verify_mobile_hud_controls.gd. With the touch-platform flag enabled in the test, the authored HUD showed the virtual joystick and avatar-switch button, kept the interact button hidden until an interaction prompt exists, and passed the mobile-control visibility check; exit 0.

## Follow-up gameplay and summon verification — 2026-11-18

- Re-ran live Royal Gardens touch movement from a fresh scene instance for 60 physics frames per direction. Right, left, up and down all moved the player; result: 4/4 directions passed. The only collision in this run was the expected Grand Fountain base when approaching from the south; no change to fountain collision was made.
- Added `tools/verify_summon_presentation_assets.gd`. It verifies both banner costs (120 / 1,200), all six 128×128 currency icon textures, the icon-plus-amount-only currency chip structure, all four reveal video resources, and the reveal overlay's cinematic player and close control.
- Summon presentation asset validation passed: `SUMMON_PRESENTATION_ASSETS_OK`, exit 0.
- This test confirms resources and scene wiring load; it does not claim a physical-device playback test of the summon videos. The actual reveal sequence remains opening video followed by rarity-specific video, then the result cards.


## Gerald four-direction funny walk import — 2026-11-18

- Imported all 64 transparent source PNGs (128x128) into assets/characters/gerald/generated/gerald_walk_4dir_16x128/.
- Replaced Gerald's cardinal walk animations in world_sheet.tres: walk_0=front/down, walk_2=right, walk_4=back/up, walk_6=left. Each has 16 unique frames and loops at 12 FPS.
- Preserved existing diagonal walk animations (walk_1, walk_3, walk_5, walk_7) and all non-walk states.
- Added a narrowly scoped validator exception for Gerald's four new 128x128 cardinal walk animations; all other world frames retain the 96x128 standard.
- Backed up the original resource to assets/characters/gerald/world_sheet.tres.pre_funny_walk_20261118.bak.
- Import verification passed: all 64 frame files imported, all four animations have 16 distinct textures, SpriteFrames validation reports 0 errors, and ActorVisual runtime test selected the correct front/right/back/left textures. Exit 0.
- Full project suite: 2572 passed, 0 failed; Godot exit 0. The test harness emitted its pre-existing SaveService invalid-profile warning and ObjectDB/resource teardown warnings, but no test failures.

## Summon reveal runtime fix — 2026-11-18

- Found and fixed a Godot 4.7 runtime error in `scripts/ui/components/summon_reveal_overlay.gd`: `VideoStreamTheora` has no `get_length()` method. The old watchdog calculation threw during every reveal.
- Replaced the invalid query with bounded watchdog values derived from the source clips: 12 seconds for the 8.064-second opening and 8 seconds for the approximately 5.05-second rarity clips. Normal `VideoStreamPlayer.finished` completion still wins; watchdog is the failure fallback.
- Added `tools/verify_summon_reveal_playback.gd`. Common, Epic and Legendary reveal sequences all emitted `reveal_finished` exactly once; headless QA completed via the watchdog fallback. Result: `SUMMON_REVEAL_PLAYBACK_OK`, exit 0.
- Important test boundary: headless QA validates sequence progression and timeout recovery, not visual decoding or finished-signal playback on a physical device.

## Garden scene alignment and regression pass — 2026-11-18 23:29

- Found a double-transform issue in the reusable castle collection: its root carried the preview placement (-416, -196) at scale (1.65, 1.65), while each host scene also needs to own placement. This caused the live castle to inherit inconsistent transforms and, when temporarily compensated, moved castle collision footprints across the fountain loops.
- Corrected the scene ownership: the reusable `reverie_royal_gardens_castle_collection.tscn` root is now neutral (position 0,0; scale 1,1). The preview scene owns a separate placement wrapper at (-416,-196), scale (1.65,1.65). The live playable scene owns a wrapper whose transform is normalized against the garden root (local position 0,-36.8; local scale 1,1.32), so its resulting global transform matches the preview exactly.
- Added `_apply_castle_architecture_transform()` to the live garden composition root to enforce that authored wrapper transform after child setup. This is a transform/layout correction only; all castle artwork and collision shapes remain authored scene nodes.
- Extended `tools/qa_castle_scale_and_fences.gd` to assert the live global castle transform. It passed: global position (-416,-196), global scale (1.65,1.65), 25 fence sprites, two side-gate archways, and expected keep/gate scales.
- Re-ran the focused garden checks after neutralizing the collection root: playable road scene passed with 10 road polygons and player spawn on road/clear 4 of 4 directions; curved connectors 80/80 clear; fountain perimeter loops 430 directional probes, 0 blocked and 0 outside samples; lower gate approaches 48/48 clear; promenade 28/28 clear. All scripts exited 0.
- Re-ran touch integration after the transform correction: live garden touch movement passed right/left/up/down (4/4, approximately 315 px per 60-frame input); mobile HUD showed joystick and avatar-switch controls and correctly gated interact; virtual joystick touch start/drag/release passed.
- The fountain sampler reports one near-parallel edge ray at EastFountainGardenLoop angle 38; it interpolates that sample from the preceding valid in-polygon point. The final 72 samples per loop remain valid and the physics probes pass.
- These are automated Godot scene/input/collision checks, not a manual visual review in the running game or a physical handset test. Summon video decoding is still not verified on a physical device; headless sequence testing exercised the watchdog fallback.
- No Git commit, merge, or push was performed.

## Summon reveal GUI runtime verification — 2026-11-18 23:43

- Fixed a completion race in `scripts/ui/components/summon_reveal_overlay.gd`: the VideoStreamPlayer `finished` signal and watchdog timeout are now armed before `play()`, rather than connecting the completion signal after playback begins. The not-playing early-return path disconnects both callbacks cleanly.
- Ran the actual reveal test with Godot 4.7.2 using the NVIDIA OpenGL Compatibility renderer (not headless). The opening cinematic visibly rendered in the live window, and the common, epic, and legendary sequences each completed exactly once.
- Runtime output: `REVEAL_SEQUENCE_COMPLETED rarity=common`, `epic`, `legendary`, then `SUMMON_REVEAL_PLAYBACK_OK`; process exit code 0; runtime 41.30 seconds.
- Captured the live opening cinematic at `docs/qa_captures/summon_reveal_runtime.jpg`. The later rarity capture was interrupted by another desktop window taking focus, so the three sequence completions are confirmed by the GUI runtime test but only the opening frame is retained as a visual capture.
- The GUI test loads GameState and read the existing save (3 characters, 3 in party, 1,500 crystals, 500 gold); it did not execute a pull or mutate save data.
- This verifies playback sequence and decoder completion on this Windows/NVIDIA setup. It is not a physical handset test.

## Single-world ownership regression — 2026-11-18 23:5x

- Investigated whether the visible overlap came from multiple world scenes being mounted at once. The live `GameWorldSessionComponent.build_world()` already clears all WorldHost children before instantiating the requested region; verified by exercising the actual `game.tscn` composition with a clean in-memory session.
- Added reusable runtime QA scene `tools/qa_single_world_host_runtime.tscn` / script `tools/qa_single_world_host_runtime.gd`. It builds Royal Gardens, switches to Greenward, then returns to Royal Gardens and checks the host after each transition.
- Results: initial host = [World_castle_royal_gardens]; after Greenward = [World_greenward]; after return = [World_castle_royal_gardens]; global `world` group count = 1; `SINGLE_WORLD_HOST_OK`. Exit code 0.
- Inspected the live Royal Gardens tree: one world root, one terrain assembly, one visible road assembly with 10 authored road polygons; the baked TileMapLayer candidate is hidden while the hand-built terrain is active. No second full map scene or second terrain assembly is mounted inside Royal Gardens.
- The three fountains are distinct authored features (West Blue Royal Fountain, East Lotus Fountain, Grand Angel Fountain); the expansion also contains a separate small decorative fountain marker. These are not duplicate world scenes. The screenshot's apparent second-map appearance is not reproduced by the current one-world runtime QA, so do not remove these designed landmarks on the basis of overlap suspicion alone.
- Current finding: scene ownership is verified to prevent simultaneous region maps in WorldHost. If the user's live view still shows map-sized duplication after a clean restart, capture that exact live screen and inspect the specific duplicated region before changing any more authored environment content.

- Captured a live Garden scene review after the transform correction at `docs/qa_captures/royal_gardens_live_20261118.jpg`. Visual inspection shows the castle keep centered over the grand gate, the stone approach aligned beneath it, and the garden systems surrounding the main route; no duplicated/overlapped world map layers are visible in this capture. This is a single runtime screenshot, not a full art-direction sign-off.

- Post-alignment content and castle-collection validators passed: `validate_content.gd` and `validate_reverie_royal_castle_collection.gd` both exited 0; the latter confirms the authored asset collection still contains two towers, four walls, two corners, one gatehouse and one keep.

## Live map visual correction — 2026-11-19

- Captured the actual running Royal Gardens game window (not the editor preview) at `docs/qa_captures/game_window_printwindow.png`. It showed the palace's built-in main entrance plus a second standalone ornate gatehouse in the same castle collection, in addition to the garden's outer front gate. The extra threshold made the vertical composition read as a second castle/map layer.
- Backed up `reverie_royal_gardens_castle_collection.tscn` to `reverie_royal_gardens_castle_collection.tscn.pre_duplicate_gate_removal_20261118.bak` and removed only the redundant `GrandGatehouse` instance and its now-unused PackedScene reference. Preserved the palace, two towers, four walls, two corner modules, all garden fences, and the outer front-perimeter gate.
- Reloaded the live `game.tscn` composition through `qa_live_garden_visual.tscn` after the edit. Final visual capture: `docs/qa_captures/garden_final_visual_after_reload.png`. The scene now presents one rear palace entrance and one outer garden gate with the promenade/fountain court between them.
- `qa_castle_scale_and_fences.gd`: PASS; 25 fence sprites, castle global position (-416,-196), scale (1.65,1.65), and no duplicate GrandGatehouse.
- Road/collision regression: 10 road polygons; gate approaches 48/48 clear; curved connectors 80/80 clear; fountain perimeter 430 probes with 0 blocked and 0 invalid centerline samples; promenade 28/28 clear. All five focused tests exited 0.
- WorldHost transition regression: Royal Gardens -> Greenward -> Royal Gardens; exactly one world child and one world-group member after return. PASS. Content validation also passed.
- The scene tree still has one terrain assembly and one hand-designed road assembly; this change corrects duplicate castle-threshold artwork rather than deleting a map or flattening any scene.
- Save data was not changed. No Git commit, merge, or push was performed.

- Follow-up note: the world-host test continues to emit a small ObjectDB/resource teardown warning at process exit even after the test explicitly frees its temporary game instance and yields one frame. Functional result remains PASS; the shutdown warning is still an open test-harness cleanup item and is not described as leak-free.

## Live Royal Gardens visual correction — 2026-11-18 23:58

- Opened the actual running Godot 4.7.2 game scene on the ASUS PC and inspected a full-screen live capture, rather than relying on the scene tree or headless preview.
- The live view exposed four oversized 2x1 hedge props sitting on or too close to the hand-authored road ribbons. Their centers were inside the West Fountain Garden Loop / Grand Fountain Parterre Loop, or their sprites intruded into the walkable corridor.
- Relocated all four hedge placements to the outer garden perimeter while retaining the same authored hedge scenes and collision shapes:
  - Hedge_1: grid (27,12) -> (17,4)
  - Hedge_2: grid (35,12) -> (48,4)
  - Hedge_3: grid (33,15) -> (50,10)
  - Hedge_4: grid (28,17) -> (20,25)
- Added a dedicated regression check in `tools/qa_garden_hedge_road_overlap.gd` / `tools/qa_garden_hedge_road_overlap.tscn`. It confirms all four placements maintain at least 160 local road-polygon units of clearance from every authored road ribbon: 4/4 pass.
- Shortened the in-world portal label to “Sealed Road” while preserving the full interaction prompt “Sealed: Road to the Gothic Castle”. The label is now centered in a fixed-width 240px plate with outline, preventing the long prompt from running across the central road.
- Final live capture: `docs/qa_captures/royal_gardens_final_live_check.png`. The central stone route is visually clear of the large hedge blockers and the portal label is compact.
- Focused collision QA after the changes: road spawn 4/4 clear; fountain perimeter 430 directional probes with 0 blocked and 0 invalid centerline samples; gate approaches 48 probes / 0 blocked; curved connectors 80 probes / 0 blocked; promenade traversal 28 probes / 0 blocked. All six focused test processes exited 0. The fountain diagnostic still prints one informational `INVALID_DETAIL` line for EastFountainGardenLoop angle 38 despite all centerline samples being valid and the collision suite passing; it is retained for follow-up, not hidden.
- The repeated vertical fence segments visible at the far-left map edge belong to the authored OuterWest perimeter fence run, not a second world or duplicate castle scene. The top keep and lower entrance gate are separate authored castle landmarks.
- This is a live visual correction and sampled collision verification; it is not a full art-direction sign-off for every camera position or device aspect ratio.

## Royal Gardens clutter reduction pass — 2026-11-19

- Responded to the user's live screenshot showing excessive overlap and visual congestion. Backed up the authored scene files before editing:
  - `castle_flora_assembly.tscn.pre_clean_layout_20261119.bak`
  - `castle_props_assembly.tscn.pre_clean_layout_20261119.bak`
  - `castle_garden_fence_assembly.tscn.pre_clean_layout_20261119.bak`
  - `castle_expansion_approach_placements.tscn.pre_clean_layout_20261119.bak`
- Reduced redundant scene layers without flattening or generating art:
  - Disabled the extra pathside planting, upper parterre planting, outer cloister niches, north ceremonial approach courts, outer seating alcoves, and south cloister extensions in the flora assembly. The reusable scenes remain in the project and can be restored individually.
  - Kept the signature tree frame, rose architecture/gazebo, and the small curated parterre flowering nodes.
  - Hid the dense promenade flower borders, fountain flowerbeds, outer garden enrichment, outer garden parterre beds, and border accents. This removes multiple overlapping shrub/hedge clusters from the same footprints.
  - Hid the redundant gothic entrance arches and secondary lantern/bench/statue furnishing layer in the props assembly; kept primary banners, lanterns, guardian statues and principal seating.
  - Hid the inner FenceRuns layer (pathside fences, court rails and promenade balustrades) while retaining the front perimeter gate, side-gate arches, outer side fence runs, and north perimeter fence. This clears the road edges and leaves the actual garden boundary.
- Simplified the authored expansion markers: retained a sparse mirrored tree/rose/hedge frame; disabled overlapping duplicate trees, the extra small fountain, duplicate statue, banner and border-post markers. Repositioned the east oak markers to grid (50,9) and (50,20) to balance the west tree line. Disabled markers remain in the scene for reversible editing.
- Visual review capture after reload: `docs/qa_captures/garden_clean_layout_pass4.png`. The main road, fountain court, palace, gazebo, and outer gate are now individually legible; inner fence clutter and overlapping planting layers are reduced. This is a cleanup pass, not a final art-direction sign-off.
- Regression results after these visibility/marker changes: gate approaches 48/48 clear; curved connectors 80/80 clear; fountain perimeter 430 probes, 0 blocked and 0 invalid centerline samples; promenade 28/28 clear; castle scale/fence structure QA passed; content validation passed. All six test scripts exited 0.
- Save data remains untouched. No Git commit, merge, or push performed.

## Symmetrical Royal Gardens recreation — 2026-11-19

- Rebuilt the active Royal Gardens presentation around the user's approved simplified reference. New reusable, editor-authored scene: `scenes/world/castle_gardens/components/castle_symmetric_garden_layout.tscn`.
- The layout is deliberately mirrored around the garden's central axis (local x=640): paired pink blossom trees, wisteria, white blossom trees, cypress, hedge/flower beds, lanterns, guardian statues and benches. Seven explicit left/right pairs are checked by `tools/qa_symmetric_garden_layout.gd`.
- Replaced the stacked modular castle facade in the live castle collection with the single complete `grand_royal_palace.png` artwork plus its matching collision footprint. The palace artwork already includes its own towers, wings and entrance; separate tower, corner and wall modules were visually duplicating its silhouette. One palace instance remains. Backups: `reverie_royal_gardens_castle_collection.tscn.pre_duplicate_gate_removal_20261118.bak` and `reverie_royal_gardens_castle_collection.tscn.pre_single_palace_rebuild_20261119.bak`.
- Live `Flora` and `Props` legacy assemblies are hidden, not deleted. The new layout replaces their overlapping decorative composition. Expansion placement assets are marked disabled (22); the separate collectible marker remains. ExpansionFlora/ExpansionProps remain visible so the Gardener's Seal Cache and Royal Road portal still spawn. This avoids hiding progression interactions when removing redundant decoration.
- Switched terrain rendering to the baked isometric TileMap base ground and its sparse variation layer. The baked `Paths`, `Water`, `FlowerDetails`, `Hedges`, `Vegetation` and `Foreground` layers are hidden so they cannot create a second road/prop map over the active hand-designed road assembly. The 10 Polygon2D hand-designed roads and fountain/water assemblies remain the authoritative paths and water. Terrain config and baked scene backups use suffix `.pre_ground_texture_compare_20261119.bak`.
- Live-game visual capture after the rebuild and baked-ground comparison: `docs/qa_captures/symmetric_rebuild_live_game_baked_ground.png`. It was captured from the running Godot game, not the editor. The camera view is player-relative, so this is a gameplay viewport capture rather than a full-map design sheet.
- Regression results:
  - `qa_symmetric_garden_layout.gd`: 7 mirrored pairs; 0 active redundant expansion assets; cache and portal preserved; one palace; 10 road surfaces. PASS.
  - `qa_castle_scale_and_fences.gd`: 25 perimeter fence sprites; one palace; castle transform preserved. PASS.
  - `qa_royal_garden_render_layers.gd`: ground < road edge < cobblestone draw order; one palace. PASS.
  - `validate_royal_garden_baked_layers.gd`: 4,997 ground cells, 109 variations, 133 path cells, 12 water cells, 6 flower cells; isometric projection matched. PASS.
  - `validate_royal_garden_ground_layers.gd`: all 8 authored TileMapLayer resources valid. PASS.
  - Road traversal: gate approaches 48/48, curved connectors 80/80, fountain perimeter 430 probes with 0 blocked and 0 invalid centerline samples, promenade 28/28. PASS.
  - Live touch movement: 4/4 cardinal directions; right/left/down unobstructed; north movement stops at the central fountain's intentional collision. PASS.
  - `validate_content.gd`: PASS.
- The fountain perimeter script reports one non-failing `INVALID_DETAIL` note at an edge ray on the east loop; its invalid centerline sample count remains 0, blocked count 0, and exit code 0.
- Save data was not changed. No Git commit, merge, or push performed.
