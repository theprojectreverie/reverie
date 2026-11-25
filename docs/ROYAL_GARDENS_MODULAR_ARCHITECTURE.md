

# Royal Gardens Castle Collection — Modular Production Notes

## Scene catalogue

### Primary structural modules
- `reverie_royal_wall_x.tscn`: reusable illustrated wall segment with ground-footprint collision.
- `reverie_royal_wall_y.tscn`: rotated illustrated wall run with matching footprint collision.
- `reverie_royal_corner.tscn`: illustrated corner-tower module with footprint collision.
- `reverie_royal_gatehouse.tscn`: illustrated ornate gate sprite with a separate ground footprint.
- `reverie_royal_battlement.tscn`: illustrated wall crown segment with footprint collision.
- `reverie_royal_keep.tscn`: main illustrated palace facade with a ground-footprint collision.
- `reverie_royal_tower.tscn`: repeatable illustrated tower sprite with footprint collision.

### Garden assemblies
- `castle_flora_assembly.tscn`: blossom trees, wisteria, cypress, rose arches, gazebo, flower pedestals and individual flowering shrub/hedge sprites.
- `castle_props_assembly.tscn`: benches, guardian statues and royal banners.
- `castle_water_assembly.tscn`: illustrated angel fountain and water-zone markers.
- `reverie_royal_gardens_castle_collection.tscn`: composed palace facade, flank towers, illustrated wall modules, corner towers and ornate gate.

## Asset source and preparation
- Original downloaded collection is preserved under `assets/reverie_custom/royal_gardens/`, organized by the original asset categories.
- Cleaned, individually cropped runtime sprites are under `assets/reverie_custom/royal_gardens/production/`.
- Production crops preserve native pixel dimensions and alpha; no upscaling or resampling is applied during crop preparation.
- Atlas captions, neighboring sprite fragments and separator lines are excluded from the production crops where identified.
- Keep the original source sheets intact. If a crop needs refinement, regenerate it from the original source rather than repeatedly editing the production PNG.

## Coordinate and composition rules
- Keep the existing 64×32 isometric world convention: one grid step is 64×32 screen pixels.
- Place architectural sprites by their ground-contact origin; offset tall artwork upward without moving its collision footprint.
- X-axis wall runs advance down-right; Y-axis wall runs advance down-left.
- Keep the gate passage visually and physically clear.
- Wall, tower and keep collisions use ground-footprint polygons, not full visible silhouettes, so tall roof pixels do not block movement.
- Keep reusable parts as independent PackedScenes; assemblies should instance them rather than duplicate scene geometry.

## Art direction
- Use the downloaded illustrated sprites as the visible artwork: moonstone/ivory stone, blue-violet roofs, antique rose-gold trim, deep violet recesses, pink/wisteria blossoms and restrained warm window light.
- Do not add generic Polygon2D/Line2D shapes, colored rectangles or geometric placeholder buildings as visible architecture or garden decoration.
- Code remains appropriate for scene assembly, y-sorting, collision, interaction, navigation and subtle non-art runtime effects.
- Do not stretch sprites to fit a space. Prefer correct source variants and proportional scaling.

## Runtime collision notes
- Wall, tower and keep scenes own their ground-footprint collision polygons.
- Gatehouse collision must not obstruct the central passage.
- Decorative trees, shrubs, benches, statues, arches and gazebo are visual props; add collision only where gameplay requires it.
- Verify collision layer 1 against the player body's configured collision mask in the target map before release.

## Asset-first conversion pass (2026-11-17)
- Imported the user's downloaded `Reverie_Royal_Gardens_Individual_Sprites.zip` into `assets/reverie_custom/royal_gardens/`.
- Prepared a production sprite set from the palace, tower, gate, wall, corner tower, trees, shrubs, rose arch, gazebo, fountain and flower pedestal source images.
- Replaced visible keep, tower, gatehouse, wall, corner and battlement geometry with illustrated sprite artwork. Collision remains separate and footprint-based.
- Rebuilt the active castle composition around one palace facade, two flank towers, illustrated wall sections, corner towers and the grand ornate gate.
- Expanded flora with individual pink/purple/white shrubs and rose hedge sprites around the formal parterres.
- Replaced the earlier polygon-heavy flora/prop/water assembly artwork with the downloaded custom sprites.
- Godot 4.7.2 reimported the new production PNGs. The actual `castle_royal_gardens.tscn` loaded headlessly with exit code 0 after cleanup of scene-file contamination.
- Remaining QA: inspect the live scene at gameplay zoom, refine exact sprite scale/ground anchors and y-sort order, check gate passage and player collision, then run the full regression suite. A successful headless load is not proof of visual perfection.

## Production rule
The active Royal Gardens must remain asset-first. Do not reintroduce generic geometric artwork as a shortcut. Add missing visual assets as purpose-made sprites, then instance them through modular scenes.


## Courtyard composition pass (2026-11-17)
- Added the imported blue royal and lotus fountain sprites as the west/east water features, retaining the angel-tiered fountain as the central garden landmark.
- Replaced the placeholder prop arrangement with the dedicated gothic archway, royal banner, lantern post, robed guardian statue, ornate stone bench and flower bench sprites.
- Repositioned the new props into paired entrance and garden groupings with clear central circulation.
- Updated the full preview scene to instance the same custom castle, flora, props, water and pathway assemblies as the production art set.
- Reimported all eight newly prepared PNGs through Godot 4.7.2.
- Verified the full preview scene loads and the asset-first castle garden smoke test passes.
- Remaining: visual QA at gameplay camera zoom, refine positions and collisions, and replace/extend path coverage only with matching authored path artwork.


## Garden circulation and legacy preview cleanup (2026-11-17)
- Removed the repeated `path_cobble_01.png` sprite strip from `castle_pathways.tscn`; it was a separate non-custom texture and created a narrow, visually disconnected promenade.
- Retained the dedicated Royal Garden path/water atlas and its isometric TileMapLayer as the approved source for garden circulation artwork.
- Expanded formal rose parterres with paired hedge borders and pink, purple and white flowering shrub groupings using the bespoke extracted sprites.
- Expanded water landmarks to the custom blue royal fountain, lotus fountain and angel-tiered fountain sprites.
- Updated props with the custom gothic archways, banners, lantern posts, guardian statues and seating sprites.
- Replaced the legacy `royal_garden_environment_preview.tscn` polygon-decoration preview with the full asset-first preview assembly, preventing the older generic Polygon2D courtyard artwork from remaining the preview target.
- Verified the actual `castle_royal_gardens.tscn`, full preview and asset-first smoke test in Godot 4.7.2; all completed with exit code 0 / PASS.
- Remaining visual QA requires an editor/gameplay screenshot to confirm final path coverage, scale, sorting and collision behavior.


## Follow-up visual repair pass (2026-11-17)
- Replaced the repeated rectangular rose hedge-block sprite references in the formal parterres with the dedicated round rose shrub artwork to remove the hard black-backed box appearance.
- Removed horizontal atlas separator rows from the purple, violet and white flower-shrub production crops; verified the cleaned individual PNGs visually.
- Rebuilt the empty Paths TileMapLayer as a three-tile-wide ceremonial promenade with a widened entrance apron, using only the dedicated Royal Gardens stone-path atlas (65 cells, atlas row 0).
- Added a focused Godot validation script checking all path cells use the approved atlas and that the flora assembly no longer references the rectangular hedge-block sprite.
- Godot 4.7.2 asset reimport completed with exit code 0; focused path/flora QA passed; full castle garden asset-first smoke test passed.
- Collision red overlays are editor collision visualization, not runtime art; do not delete gameplay collision shapes to hide editor overlays.

- Added a symmetric promenade planting border: eight individually illustrated rose, white-flower and violet shrub sprites, placed outside the three-tile stone walkway with matching west/east offsets.
- Verified the full garden component smoke test after the additional sprite placements (Godot 4.7.2, exit code 0).


## Composition cleanup pass (2026-11-17)
- Audited the production PNG sprite set for alpha transparency; the inspected palace, gate, rose arch and shrub artwork uses transparent backgrounds. The red/orange shapes visible in the editor screenshot are collision debug overlays, not opaque image backplates.
- Replaced the three-lane promenade tile placement with one centered run of 22 authored isometric stone-path tiles.
- Reduced entrance crowding by redistributing the two side fountains, central fountain, guardian statues, gazebo and seating into a more open, symmetrical garden sequence.
- Verified the asset-first castle garden component smoke test in Godot 4.7.2 (exit code 0).


## Water layout cleanup (2026-11-17)
- Reorganized the 12 loose water atlas tiles into two contiguous 3x2 isometric pond footprints.
- Removed the old placements near the castle approach and aligned the new pond centers to the west/east fountain sprite centers (world positions 352,688 and 928,688).
- Kept the approved custom water tileset and preserved the existing WaterZones gameplay markers.
- Added a focused Godot validation script; confirmed exactly 12 water tiles, all from atlas source 0 / tile (0,2), grouped into the two intended footprints. Godot 4.7.2 QA passed.

## Reference composition pass (2026-11-18)
- Replaced the runtime StonePathways placement script with a reusable static road-surface scene. The scene contains six static Polygon2D cobblestone ribbons using the seamless custom `royal_cobble_ribbon_96.png` texture with pixel-space UVs and enabled texture repetition: the central grand promenade, mirrored west/east fountain loops, a grand fountain parterre loop and two connecting paths.
- castle_pathways.tscn and the legacy stone_pathways.tscn now instance the same static road assembly; no runtime path-cell painting is used.
- Enlarged the modular royal castle assembly to 1.30x and its keep to 1.22x while retaining the established entrance alignment.
- Extended the existing custom fence atlas assembly with a front perimeter fence, a central ornate gate sprite, decorative gateposts and outer side fence runs. Added eighteen additional individually placed flower-shrub sprites around the lower and outer garden loops.
- Replaced preview-only generated lighting and camera scripts with authored scene nodes. The fountain and promenade glows are static PointLight2D nodes using a GradientTexture2D subresource.
- Replaced the gameplay garden light's generated radial image with a static GradientTexture2D resource in castle_garden_light.tscn; the lighting component now instances the authored light scene without creating a texture at runtime.
- Godot 4.7.2 smoke tests passed for both castle_royal_gardens.tscn and reverie_royal_gardens_full_preview.tscn; baked isometric terrain validation remained PASS.
- GitHub publishing was not part of this pass.
- Kept the original 133-cell baked Paths layer hidden as a preserved legacy reference. The six-ribbon road assembly now supplies the complete central promenade and garden branches in both the live map and the preview, avoiding dependence on the intentionally hidden TilemapCandidate terrain instance.


- Reframed the full-scene preview camera to position (640, 620) at 0.44 zoom for a balanced castle-to-garden review composition.
- Re-captured the live Godot preview and visually checked the full castle-to-garden layout; the continuous textured branches now join the central promenade and frame the fountain courts, with the gate, flowering parterres and perimeter fence retained.
- Re-ran the production castle scene smoke test, full preview scene smoke test and baked isometric layer validation in Godot 4.7.2. All passed; baked scene reports 2,929 ground cells, 44 variations, 133 path cells, 12 water cells, 6 flower cells and 8 layers.

- Completed the decorative perimeter with north-corner fence runs, continuous outer side sections and an enlarged front entrance gate; the existing perimeter collision remains intact.
- Set the road ribbon half-width to 42 world units after live visual comparison; this keeps the central route and side courts clearly readable while retaining the custom cobblestone detail.

- Reframed the full-scene preview camera to position (640, 720) at 0.32 zoom so the castle, gate, three fountains, side garden loops and lower parterre read together in a single overview.
- Final Godot 4.7.2 QA: production castle scene load PASS; full preview scene load PASS; baked isometric terrain PASS (2,929 ground cells, 44 variations, 133 preserved legacy path cells, 12 water cells, 6 flower cells, 8 layers); static road/flora/atmosphere QA PASS (6 ribbons, 38 fountain-bed sprites, 5 preview lights, ambient petals enabled).
- The central promenade and five branching garden ribbons are all authored from the same seamless custom cobblestone texture and shared by the production map and preview scene.

## Garden finish pass (2026-11-18)
- Added a reusable `castle_road_edge_transitions.tscn` module: 45 individually placed cells from the existing hand-painted isometric ground atlas, layered between grass and custom cobblestone ribbons.
- Added `castle_pathside_planting.tscn` with 16 individually positioned pink, white, violet and rose shrub sprites to strengthen the side-loop edges.
- Added `castle_upper_parterre_planting.tscn` with eight custom shrub sprites to fill the upper castle garden shoulders symmetrically.
- Refined the west/east fountain loops and central parterre road centerlines with additional hand-authored control points for softer curves; the resulting six road ribbons remain static scene geometry using the custom cobblestone texture.
- Shifted the full preview ambient palette toward a cooler twilight violet and restored the overview camera to 0.32 zoom for whole-garden review.
- Godot 4.7.2 QA passed for the production castle, full preview and static asset checks: 6 custom road ribbons, 45 hand-painted edge transition cells, 38 fountain flowerbed sprites, 16 pathside sprites, 8 upper-parterre sprites and 5 preview lights.
- Final overview camera framing is position (800, 800) at 0.32 zoom, keeping the upper castle and lower entrance in the review composition.

## Outer cloister finish pass (2026-11-18)
- Added `castle_outer_cloister_niches.tscn` as a reusable paired west/east garden assembly, using the custom illustrated wall segment, banner wall, spire tower, flower bench, lantern post and flowering shrub assets.
- The paired niches add eight architectural sprites and eight garden/furnishing sprites, framing the outer courts without blocking the central gate or promenade.
- Added two low-energy warm lantern glows to the full-scene preview at the west/east cloister lantern positions; the fountain and promenade lighting remains unchanged.
- Extended static asset QA to verify both cloister architecture groups and the two added preview lights.

## Northern castle approach pass (2026-11-18)
- Added `castle_north_approach_courts.tscn`, a paired west/east ceremonial approach assembly using the existing custom tower module, ornate wall segment, royal banners, lantern posts, guardian statues and flowering shrubs.
- Each court is a separate y-sorted subassembly with seven purpose-built illustrated sprites; the central cobblestone promenade remains unobstructed.
- Added two subtle warm approach lantern glows to the preview lighting scene, bringing the authored preview lights to nine.
- Extended the static garden QA to verify both approach courts and their complete seven-sprite assemblies.
- Added `NorthCastleThresholdApron` as a hand-authored, rounded static Polygon2D plaza using the same seamless custom cobblestone texture and UV mapping as the existing road assembly; it widens the central promenade into a ceremonial threshold immediately before the gate.
- Increased the paired north approach spire, wall, banner and lantern sprite scales for stronger visual hierarchy while preserving left/right mirroring and keeping the central passage open.
- Added paired `OuterGardenSeatingAlcoves` at the west/east outer garden edges. Each uses the custom flower bench, rose hedge block, distinct flowering shrubs and a lantern post; both are separate y-sorted assemblies.
- Added two low-energy warm bench lantern glows to the preview lighting rig and extended static QA to verify all ten seating sprites and both light anchors.
- Added `SouthOuterCloisterExtensions`, a paired west/east lower perimeter architecture pass using the existing wall segment and banner-wall art, with rose and white flowering accents. Mirrored placement extends the cloister rhythm down the garden sides without changing the central promenade.

- Restored the six authored static cobblestone ribbons from the dedicated road-authoring scene: central promenade, west/east fountain loops, grand fountain parterre loop, and west/east parterre connectors. Each ribbon retains its explicit polygon UVs and the approved custom cobblestone texture; the assembly sits at z=-28 so the terrain and road-edge layer ordering remains deliberate.
- Corrected the playable world's PathwayTiles parent z-index to 10. The road assembly's effective z becomes -18, just above the generated grass Terrain at -20; previously the child road layer could be sorted behind the production terrain even though the isolated preview showed it correctly.
- Added tools/qa_royal_garden_road_ribbons.gd. It loads the playable world, verifies all six Polygon2D ribbons, confirms authored UV/texture assignments, and checks that the effective road z-order is above terrain.
- Validation: playable world scene load, full preview scene load, baked isometric layer validation, and the new playable road-ribbon QA all pass in Godot 4.7.2. New QA reports six ribbons and effective road z=-18 above terrain z=-20.

- Refined the road hierarchy once more: the central promenade now begins at the castle threshold instead of running behind the keep, and a dedicated NorthCastleThresholdApron widens the arrival court. The six garden ribbons plus the threshold apron are seven individually named Polygon2D nodes, all using the authored UV mapping and custom cobblestone texture.
- Updated the road QA contract to require the seventh apron node. The enrichment suite now passes again with 7 road modules, 38 fountain-bed sprites, 11 preview lights, 45 hand-painted edge cells, and all existing pathside/upper-parterre/cloister/court/seating assemblies present.
- Final road QA confirms seven Polygon2D modules, matching polygon/UV counts, the custom cobblestone asset, and playable effective z=-18 above terrain z=-20.

## Thorough reference-composition refinement (2026-11-18)
- Corrected the shared road/terrain draw order. The hand-painted transition tilemap now renders at absolute z=-19, between terrain (-20 in the playable world / -30 in the preview) and the cobblestone ribbons (-18 effective z in both). The preview PathwaySystem is aligned to z=10 so its road assembly matches the playable PathwayTiles ordering.
- Re-authored the west and east fountain walkways as open U-shaped ribbons rather than closed self-intersecting loops. They now curve around the side fountains and open toward the central promenade.
- Added width hierarchy to the static road modules: central avenue 96px, side fountain loops 68px, central fountain court 84px, parterre connectors 64px, lower gate walks 60px, and castle threshold apron 100px. All surfaces continue to use the custom royal_cobble_ribbon_96.png artwork and authored UVs.
- Added two lower curved garden walks that connect the south parterre connectors to the new side entrances, bringing the static road assembly to nine named Polygon2D modules.
- Added a modular castle_side_gate_arches.tscn using the custom gothic_archway artwork. Opened two matching gaps in the front perimeter fence, removed the four obstructing rail segments, and placed mirrored side arches at the new openings.
- Increased the north and outer side fence rail segment scale to 1.9 so adjacent 32x32 custom fence pieces meet continuously instead of leaving visible gaps. The front fence retains its close-spaced rails and central ornate gate.
- Enlarged the castle collection to 1.4x, the keep to 1.30x, and the gatehouse to 0.98x while keeping the keep centered and adjusting the gatehouse position to preserve the entrance alignment.
- Hid the central rose gazebo from the shared garden composition so it no longer blocks the promenade to the main gate; the lower benches and the main entrance remain.
- Added six existing custom blossom/wisteria trees in a mirrored outer woodland frame to soften the grass margins around the perimeter.
- Reframed the full-scene preview camera to position (990, 800) and zoom 0.36. This is a preview-only framing change; it does not alter the gameplay camera.
- Added/updated QA for open fountain ribbons, nine road modules, road/edge/terrain ordering in both preview and playable scenes, castle scale, side-gate arches, hidden central gazebo, and six outer woodland trees.
- Godot 4.7.2 validation passed: production scene and full preview scene load; static asset QA, road ribbon QA, render-layer QA, castle/fence QA, and baked isometric layer validation all pass. Baked terrain remains ground=2929, variations=44, paths=133, water=12, flowers=6, layers=8, iso_projection=matched.
- Latest visual review: artifacts/qa/royal_gardens_final_woodland_review_20261118.png. GitHub publishing was not part of this pass.


## Simplified reference-layout pass (2026-11-19)
- The playable `castle_royal_gardens.tscn` now uses one authored grand-palace sprite with a separate ground-footprint collision, rather than rebuilding the facade from many overlapping wall/tower modules.
- The dense legacy `Flora` and `Props` assemblies remain preserved in the project but are hidden in the playable world. Do not re-enable them alongside the clean layout.
- `SymmetricalGardenLayout` is the active garden dressing: 30 individually authored sprites in mirrored canopy, garden-bed and furnishing groups. Keep the central promenade and gate approach visually open.
- The playable road assembly contains 10 separate hand-authored cobblestone polygon modules, all using the approved custom ribbon texture and authored UVs. Their effective draw order remains above terrain.
- Updated `castle_garden_component_smoke.gd` to validate the active simplified composition, mirror pairs, 194-cell connected route grid, palace artwork, visible entrance gate and all 10 road modules. The focused smoke test and road-ribbon QA both pass in Godot 4.7.2.
- Full headless editor initialization/import completed with exit code 0. A fresh live-window visual review and in-game walk-through remain required before calling the map finished.


## Playable-world clearance verification (2026-11-19)
- Extended `castle_garden_component_smoke.gd` with a real spawned-player collision check. The player spawns at (640, 1090) and all four cardinal 28px movement probes are clear.
- Road-ribbon QA passes with 10 authored Polygon2D modules, matching UVs and the approved custom texture; effective road z=-18 remains above terrain z=-20.
- Live promenade collision QA passes 28 north/south movement probes with zero blocked probes.
- A fresh playable-scene capture confirms the hidden legacy expansion flora/props no longer clutter the garden. The palace, mirrored planting, fountains, promenade and entrance are visible as a coherent composition.
- Remaining issue: the playable grass field extends well beyond the designed garden, leaving a large open southern lawn. Do not shrink world bounds or baked terrain without checking region map bounds, quest/portal destinations and chunk coverage. A live input walkthrough and composition review at normal player-camera framing are still required before marking the map complete.


## Touch movement and fountain-route QA (2026-11-19)
- Live `TouchInput` movement test completed successfully in all four cardinal directions (4/4). The player moved 315px right, 316px left, 225px north before correctly meeting the grand fountain base, and 316px south. The fountain collision is expected; the open curved bypasses are validated separately.
- Curved garden connector QA: 80 directional probes, zero blocked.
- Lower gate approach QA: 48 directional probes, zero blocked.
- Fountain perimeter QA was corrected so grazing rays are recovered from the nearest valid point on the authored road polygon and unrecoverable samples fail explicitly. Re-run passes with 430 directional probes, zero blocked, and zero invalid centerline samples.
- The earlier `qa_garden_hedge_road_overlap.gd` helper is currently stale when invoked as a standalone SceneTree script (it extends Node and expects autoloads); it was not used as evidence for the playable-world pass. The active smoke test independently verifies that legacy expansion layers remain hidden.


## Player-camera composition correction (2026-11-19)
- Live normal-camera capture showed the castle clipped at the top while the south lawn occupied too much of the lower screen.
- Adjusted the authored `Player/Camera2D` scene position from `(0, -30)` to `(0, -180)`, biasing the view north while keeping the player and world geometry unchanged. Original camera scene backed up as `player_camera.tscn.pre_garden_framing_20261119.bak`.
- The playable-world smoke test now asserts the north-biased camera position; it passes alongside the 194-cell route connectivity, 4-way spawn clearance, and clean 30-sprite / 10-road-module layout checks.
- Live touch movement remains 4/4 cardinal directions; curved connectors, gate approaches, and fountain perimeters remain collision-clear after the camera-only adjustment.
- Follow-up visual capture in the actual interactive renderer is still needed to judge the exact framing and tune further if necessary.


## New grass-to-cobble road edge assets (2026-11-19)

- Replaced the visible legacy atlas-edge layer with 45 placed Sprite2D transitions using the four approved Reverie Royal Gardens tiles: grass_path_edge_ne/nw/se/sw.png (64x32 each).
- Kept the old TileMapLayer as a hidden legacy reference; its former atlas rendering is no longer visible, and the authored road-surface polygons remain unchanged.
- Edge sprites occupy the existing 45 transition positions, preserving the authored route footprint while using the new pack artwork.
- Backup: castle_road_edge_transitions.tscn.pre_new_road_edges_20261119.bak.
- QA: qa_royal_garden_new_road_edges.gd validates all 45 sprites, the four imported texture paths, and 64x32 source dimensions. The main castle_garden_component_smoke.gd also checks the new edge layer in the playable world.
- Visual renderer review is still required to confirm edge orientation and blending at runtime; this headless QA verifies scene wiring and assets, not final pixel alignment.


## Final focused regression batch (2026-11-19)
- Re-ran the production garden component smoke test after the camera offset and road-edge import: PASS. It confirms 194 connected route cells, 4/4 player spawn clearance probes, north-biased camera offset `(0, -180)`, 45 imported grass-to-cobble transition sprites, one palace, 30 authored garden sprites and 10 road modules.
- Re-ran live touch movement: PASS (4/4 cardinal directions). Right/left/down movement remains unobstructed; the northward approach stops at the expected `GrandFountainBaseCollision` footprint.
- Re-ran curved connector collision QA: 80 directional probes, zero blocked; PASS.
- Re-ran gate approach collision QA: 48 directional probes, zero blocked; PASS.
- Re-ran fountain perimeter collision QA: 430 directional probes, zero blocked, zero invalid centerline samples; PASS.
- All five focused scripts completed in Godot 4.7.2 with exit code 0 in one sequential regression batch.
- The project was launched in the interactive renderer and the Reverie main menu opened. This confirms the project can start as a GUI game process, but the map itself was not brought into view for a post-offset gameplay-camera screenshot in this pass. Keep the visual camera framing review as an explicit remaining sign-off item; do not infer visual perfection from the headless checks.


## GPU-rendered camera composition follow-up (2026-11-19)
- A real GPU-rendered three-frame capture (`--display-driver windows --write-movie`) exposed that the `(0, -180)` camera offset still left the palace clipped at the top and too much lower lawn in view; this is direct renderer evidence, not a headless viewport capture.
- Increased the authored player-camera local Y offset to `(0, -360)` to shift the composition farther north without moving the player spawn, roads, or collision geometry.
- Added a backup before this second adjustment: `player_camera.tscn.pre_north_compose_20261119.bak`.
- The playable-world smoke assertion now expects `(0, -360)`. A new GPU-rendered frame and focused regression run are required before accepting this framing.


## Live camera composition refinement (2026-11-19)
- Captured the playable Royal Gardens in the interactive GPU renderer at fullscreen resolution. The `(0, -360)` offset with the original `0.55 / world_scale` base zoom showed the full palace but pushed too much of the southern promenade toward the bottom edge.
- Tuned the authored player camera local offset to `(0, -220)` and reduced the spawner base zoom factor from `0.55` to `0.50` (runtime zoom `0.303` at the current world scale). This is a camera-only change: no spawn, terrain, route, or collision geometry was moved.
- Added a runtime zoom assertion to `castle_garden_component_smoke.gd`. The updated smoke test passes: 194 connected route cells, 4/4 spawn clearance, camera offset `(0, -220)`, zoom `0.303`, 45 road-edge sprites, 30 authored garden sprites, and 10 road modules.
- Re-ran touch movement (4/4 directions), curved connectors (80 probes, 0 blocked), gate approaches (48 probes, 0 blocked), and fountain perimeters (430 probes, 0 blocked, 0 invalid samples); all passed with exit code 0.
- Interactive capture: `artifacts/qa/royal_gardens_camera_zoomout_20261119.png`. The palace is fully visible in the GPU-rendered frame. The wider framing still shows substantial open grass around the authored garden; this is a remaining composition/world-coverage issue, not a route-connectivity failure.
- Backup before this tune: `scenes/characters/components/player_camera.tscn.pre_composition_tune_20261119.bak`. Spawner and smoke-test backups use `.pre_camera_zoom_20261119.bak`.

## Southeast ground coverage repair (2026-11-19)
- The GPU-rendered north-biased frame exposed the baked grass tilemap ending one grid column before the southeast camera corner. The visible black wedge was traced to `ground_max.x` / `CastleLayout.GRID_MAX.x` both ending at 65 while the camera corner projects to approximately grid `(67, 20)`.
- Extended the terrain bake input and layout scan bound to X=85 while keeping `SCREEN_MAX` unchanged, so only cells inside the existing authored screen rectangle are baked.
- Rebuilt `royal_garden_isometric_layers_baked.tscn`: 5,857 ground cells, 147 sparse variations, 133 path cells, 12 water cells, 6 flower markers. Backup: `royal_garden_isometric_layers_baked.tscn.pre_southeast_ground_extension_20261119.bak`.
- Added a playable-world smoke assertion that baked ground exists at `(67, 20)`. Re-run passes with connected paths, spawn clearance, camera position `(0, -360)`, camera zoom `0.303`, 45 road-edge sprites, one palace, 30 garden sprites and 10 authored road modules.
- A later GPU capture at the current saved player position also showed the camera can expose other map boundaries when the saved player is far east. The southeast spawn-corner fix is structurally verified, but full camera-boundary framing across the entire walkable region still needs a dedicated live walk-through before sign-off.


## Camera composition re-balance (2026-11-19)
- A subsequent project-side camera tuning pass changed the player-camera local offset from `(0, -360)` to `(0, -220)` and the player-spawner base zoom from `0.55 / world_scale` to `0.50 / world_scale`. The current smoke test reflects and passes against these latest scene/component values; preserve this newer configuration rather than restoring the earlier trial.
- Final current-state checks: playable-world smoke PASS; Godot 4.7.2 editor import/scan PASS (exit 0); touch movement 4/4; curved connector probes 80/80 clear; gate approaches 48/48 clear; fountain perimeter 430/430 clear with zero invalid samples.
- The camera's full boundary framing across the saved-position extremes remains open. The GPU frame at a far-eastern saved position shows the camera can still expose the outer map boundary; do not mark visual camera sign-off complete yet.


## Camera edge clamping (2026-11-19)
- A GPU-rendered frame at the saved far-eastern player position showed the camera following beyond the authored ground rectangle, exposing large black wedges outside the map.
- The player spawner now derives Camera2D world limits from the transformed `CastleLayout.SCREEN_MIN` / `SCREEN_MAX` rectangle and applies all four camera limits. Player position, map collision, and routes are unchanged.
- The component smoke test asserts the exact transformed limits `(-1208, -600)` to `(2752, 2475)` for the current authored world transform. Smoke test passes.
- Follow-up GPU capture at the far-eastern saved position confirms the lower-right diagonal void is gone and the garden remains framed around the playable area. Very small black corner slivers remain at the extreme top edges; this is not being treated as a full visual sign-off.


## Camera framing and fence collision pass (2026-11-19)
- Interactive GPU capture review showed the previous wider camera composition clipped the lower promenade, while the original zoom left too much empty lawn in view. The current balanced framing uses player-camera local offset `(0, -220)` and base zoom factor `0.62 / world_scale_x` (runtime zoom `0.376` at the current world scale). The palace, central promenade, fountains and lower gate approaches are better balanced in the live frame.
- The visible fence assembly previously consisted of Sprite2D nodes only; there was no StaticBody2D collision, which explains why the player could walk through the rails.
- Added an authored `FenceCollision` StaticBody2D with eight RectangleShape2D segments: two north rails, two outer side rails, and four front rail sections. Collision layer 1 matches the player's collision mask.
- Preserved all three intended front passages: west side gate at local x=335, central grand gate at x=640, and east side gate at x=945. The first QA pass exposed two blocked lower-gate approach probes; the front collision was split around the two side-gate openings rather than blocking those paths.
- Added `tools/qa_royal_garden_fence_collision.gd`, which ray-tests all eight fence segments and verifies all three gate openings remain clear. Result: PASS (8 barriers, 3 openings).
- Updated `tests/castle_garden_component_smoke.gd` to require all eight fence collision segments.
- Final sequential regression batch: garden smoke test PASS; touch movement 4/4; curved connectors 80 probes / 0 blocked; gate approaches 48 probes / 0 blocked; fountain perimeter 430 probes / 0 blocked / 0 invalid centerline samples. All five scripts completed with exit code 0.
- Backups: `castle_garden_fence_assembly.tscn.pre_collision_rails_20261119.bak`, `player_camera.tscn.pre_zoom_balance_20261119.bak`, `castle_player_spawner_component.gd.pre_zoom_balance_20261119.bak`, and `castle_garden_component_smoke.gd.pre_zoom_balance_20261119.bak`.

## Royal Gardens content cleanup and Gothic Castle road opening (2026-11-19)
- Removed the Royal Gardener marker from the playable garden's authored NPC placements. The two gate guards and Pip remain; no unrelated NPC roster changes were made elsewhere.
- Removed both castle_garden_sentinels encounter spawn entries from the Royal Gardens region. The formal garden now has no roaming monsters.
- Removed the GardenerSealCache placement marker and its cache-spawner component from the playable expansion composition. The reusable cache and quest assets remain in the project but are no longer instantiated in this map.
- Removed the garden_shadows quest prerequisite from the Royal Gardens -> Gothic Castle region connection. The road portal still targets gothic_castle_boss_zone at royal_gate, and is now visible/interactable without the removed sentinel encounter.
- Kept the existing region connection, entry point, portal scene and shared quest-marker infrastructure. The old garden_shadows quest/dialogue definitions remain as dormant data for compatibility; they are not started by the cleaned map.
- Replaced the obsolete garden-interactables QA expectations with a focused content contract: exactly 3 approved NPCs (two gate guards + Pip), zero garden monsters, no cache prop, and a visible/unlocked Gothic Castle road portal.
- Extended castle_garden_component_smoke.gd to enforce the same content contract.
- Verified in Godot 4.7.2: garden smoke PASS (194 connected route cells, spawn clearance 4/4, camera offset (0, -220), zoom 0.376, 45 road-edge sprites, 8 fence barriers, 3 gate openings, one palace, 30 garden sprites, 10 road modules); runtime content QA PASS; fence collision QA PASS (8/8 barriers, 3/3 gate openings).
- Road placement inspection confirms the portal at world-local (512, 768) / grid (32, 16) is covered by the authored GrandFountainParterreLoop and WestParterreConnector road polygons. It is not a CastleLayout.is_path cell, because the actual playable road surface is the separate authored polygon assembly.
- The previous interactive renderer screenshot exposed the unrelated gardener, two sentinels and old sealed-road label. A fresh GPU screenshot after this cleanup is still required for visual sign-off.


## Fence aspect-ratio correction (2026-11-19)
- Audited the active north, outer-side and front perimeter fence sprite transforms. The north and outer-side fence groups inherited a 1.26x horizontal parent scale while their 32x32 rail sprites used a different local X/Y scale, stretching the visible fence artwork.
- Compensated the sprite-local scales for each fence orientation: north-facing horizontal rails use `(1.508, 1.9)`; rotated outer-side rails use `(1.9, 1.508)`; the decorative posts are similarly compensated. This preserves their existing world positions and target visual sizes while producing equal X/Y basis lengths in the fence assembly. Front rails remain uniformly `(1.55, 1.55)`.
- Added `tools/qa_royal_garden_fence_aspect.gd` and extended `tests/castle_garden_component_smoke.gd` to assert proportional artwork for north, side and front fence rails.
- Fence aspect QA passes: north rails 1.900x1.900, side rails 1.900x1.900, front rails 1.550x1.550; north and side posts 1.550x1.550.
- Re-ran playable-world smoke (194 connected route cells, 4/4 spawn clearance, camera offset `(0,-220)`, zoom `0.376`, 45 road-edge sprites, eight fence collision segments, three clear gate passages, approved NPC/portal content, 30 garden sprites and 10 road modules): PASS.
- Re-ran fence collision QA (8 barriers, 3 gate passages), live touch movement (4/4), curved connectors (80 probes, zero blocked), gate approaches (48 probes, zero blocked), and fountain perimeter (430 probes, zero blocked, zero invalid samples): all PASS.
- Backup: `castle_garden_fence_assembly.tscn.pre_uniform_aspect_20261119.bak`.
- This pass corrects transform proportions; a fresh in-game visual inspection is still required to judge the final fence silhouette and edge-to-edge joins.


## Extended outer-fence rail transform correction (2026-11-19)
- A live-renderer review exposed that the upper/extended outer-side fence rails were not covered by the first aspect-ratio QA sample. Those 20 sprites (10 on each side) had their compensated local X/Y scales reversed relative to their 90-degree rotation and the parent X scale of 1.26.
- Corrected the extended west and east rails to match the proven lower side-run transform: west `Vector2(1.9, 1.508)`, east `Vector2(-1.9, 1.508)`, with their existing 90-degree rotations and positions unchanged. This restores a uniform 1.9 assembly-space basis in both axes.
- Extended `tools/qa_royal_garden_fence_aspect.gd` and the main garden smoke test to sample both west and east extended rails, preventing this section from being missed again.
- Verification after the correction: fence aspect QA passes for north, lower side, both extended side runs, front rails, and north/side posts. Main Royal Gardens smoke passes (194 connected route cells, spawn clearance, camera framing/zoom/world limits, 45 road-edge sprites, 8 fence collision segments, three gate passages, approved NPC roster, palace/road and clean layout). Fence collision QA passes (8 barriers and 3 clear passages). Live touch movement passes in all 4 directions.
- A fresh desktop capture attempt was obscured by the foreground Library window, so the extended-rail transform fix is verified by scene inspection and QA, not yet by an unobstructed post-fix screenshot.
- No fence positions, collision geometry, route cells, or gate openings were changed.

## Live visual review after extended fence correction (2026-11-19)

- Captured the maximized running Reverie DEBUG window after bringing it to the foreground; the screenshot is artifacts/qa/royal_gardens_fence_postfix_review_maximized.png.
- Visual review confirms the palace artwork is fully within the camera frame, the central palace approach remains connected to the formal garden promenade, both fountain islands and the central fountain are visible, and the three approved garden NPCs are present.
- The north and extended side fence rails show no obvious remaining stretched-artwork artifact at the live camera scale. This is a visual spot-check, not a pixel-perfect texture audit.
- The garden reads as a deliberately symmetrical formal layout. The broad lawn around the estate remains open by design; small petal/ground accents are visible, but no major sprite pile-up or path obstruction is apparent in this capture.
- Regression checks run with this review: promenade traversal (28 probes, 0 blocked), garden runtime interactables (NPC roster, encounters, cache removal, portal and quest marker), fence aspect (7 samples), and fence collision (8 barriers, 3 clear gate openings). All exited 0.
- This capture is a single static view. It does not replace a full manual walk-through of every garden edge or a review at mobile aspect ratios.

## Explicit road-edge render ordering (2026-11-19)

- The former render-layer QA referenced the retired HandPaintedRoadEdgeTransitions TileMapLayer and was stale after the edge artwork was migrated to NewAssetRoadEdges.
- Updated the live QA path to the actual Node2D sprite group and set NewAssetRoadEdges.z_index = -19 with z_as_relative = false. This places the new edge sprites at absolute Z -19, between terrain Z -20 and the cobblestone road surface effective Z -18.
- Render-layer QA now passes with PLAYABLE_LAYER_ORDER=-20<-19<-18. The separate road-edge asset QA confirms all 45 hand-placed 64x32 sprites use the four approved directional textures.
- Reopened the live Royal Gardens scene after the change and captured artifacts/qa/royal_gardens_edge_layer_live.png. The palace, main road, loop promenade, fountains and approved NPCs render in the updated scene.

## Extended boundary regression and portrait aspect review (2026-11-19)

- Re-ran the outer and central movement suite after the road-edge layer change:
  - Central promenade: 28 directional probes, 0 blocked.
  - Lower gate approaches: 48 directional probes, 0 blocked.
  - Fountain-loop perimeters: 430 directional probes, 0 blocked, 0 invalid centerline samples.
  - Live touch input: all four directions moved approximately 315 px over 60 physics frames, with 0 collisions.
  - Fence: 8 collision barriers and all 3 gate openings passed.
  - Runtime interactables: only the two gate guards and Pip; no unrelated sentinel encounter or removed cache; Gothic Castle portal visible, unlocked and interactable.
  - Fence aspect: all 7 representative rail/post samples passed.
  - Render ordering: terrain -20, new road-edge sprites -19, road surface effective -18.
  - New road-edge artwork: all 45 placed sprites passed their texture/dimension checks.
- Performed a narrow portrait-window visual simulation and saved artifacts/qa/royal_gardens_portrait_aspect_review.png. The estate remains visible in the portrait viewport, but the world is vertically low in the frame with substantial unused dark space above it. This is a camera-framing issue for portrait aspect, not a movement or collision failure.
- Kept the camera configuration unchanged rather than applying an unverified offset that could damage the normal landscape framing. Portrait-specific camera centering/zoom remains an explicit follow-up.
- Restored the running game window to its normal landscape size after the portrait review.

## Responsive portrait camera framing (2026-11-19)

- Added aspect-aware vertical camera compensation in PlayerCameraRig. Landscape and square viewports retain the existing zero follow-offset baseline; portrait viewports (aspect below 0.85) receive a 500-unit vertical camera offset, with normal movement look-ahead added on top.
- The camera node's authored position (-220) and zoom remain unchanged, preserving the landscape camera contract and existing smoke assertions.
- Added tools/qa_player_camera_aspect_framing.gd to exercise landscape (1280x720), portrait (480x860), and square (720x720) SubViewports. All three cases pass.
- Re-ran the main Royal Gardens component smoke test and live four-direction touch movement test after the change; both pass.
- Captured artifacts/qa/royal_gardens_portrait_framing_trial_500.png. The portrait estate composition is shifted upward compared with the earlier 220-unit trial and the full garden remains visible. A dark clear-color band still remains above the terrain at the top of the portrait viewport; this is not considered fully resolved and requires a separate review of the camera's visible world bounds/terrain coverage.
- Captured artifacts/qa/royal_gardens_landscape_camera_regression.png as a landscape visual regression reference. The authored camera position and zoom are unchanged; the capture is a static desktop-window spot-check.


## Portrait terrain coverage extension (2026-11-19)

- Compared live portrait captures at vertical camera offsets -500, +500 and +1000. The negative offset worsened the top void; +1000 produced the best centered estate composition and is retained only for portrait viewports. Landscape and square viewports continue to use the original zero follow-offset baseline.
- The remaining horizontal dark bands in the +1000 capture were traced to the authored grass rectangle ending at SCREEN_MIN.y=-360 and SCREEN_MAX.y=2100. This was not a missing sprite or camera-only problem.
- Extended the authored screen-space grass bounds vertically to SCREEN_MIN.y=-650 and SCREEN_MAX.y=2390. The existing 32x32 baked ground atlas tiles now cover the portrait top and bottom viewing area; no new assets, props, or decorative sprites were added.
- Rebuilt the baked terrain scene with the existing bake tool: 6,433 ground cells, 176 sparse grass variations, 133 path cells, 12 water cells and 6 flower markers.
- Extended the main component smoke test to assert grass coverage at upper portrait grid (-9,-31), lower portrait grid (85,65), and the existing southeast camera sample (67,20).
- Updated transformed camera world bounds automatically through CastleLayout.SCREEN_MIN/MAX: (-1208,-963) to (2752,2838).
- Validation results: baked terrain validator PASS (6,433 ground cells; 8 layers; isometric projection matched); Royal Gardens component smoke PASS; portrait/landscape/square camera QA PASS; touch movement 4/4; promenade 28 probes/0 blocked; gate approaches 48/0 blocked; fountain perimeter 430/0 blocked/0 invalid; fence aspect 7/7; fence collision 8 barriers/3 openings; road-edge layer ordering PASS; 45 road-edge sprites PASS.
- Re-ran Godot editor import/scan after removing an accidental UTF-8 BOM from the edited castle_road_edge_transitions.tscn; the scan completed without the earlier scene parse error.
- Live portrait capture: artifacts/qa/royal_gardens_portrait_terrain_extended.png. The top/bottom horizontal clear-color bands are now replaced by grass coverage. The remaining black corner wedges follow the diamond-shaped edge of the isometric terrain rectangle; they are a separate background-treatment issue, not missing top/bottom ground rows.
- Live landscape regression capture: artifacts/qa/royal_gardens_landscape_after_terrain_extension.png. Landscape baseline offset remains zero; the authored camera transform/zoom and gameplay geometry were not changed by the portrait terrain extension.
- Backups: castle_layout.gd.pre_portrait_terrain_extend_20261119.bak and castle_garden_component_smoke.gd.pre_portrait_terrain_extend_20261119.bak.


## Portrait terrain corner coverage completion (2026-11-19)

- The first vertical terrain extension removed the horizontal bands but left black wedges at the four portrait corners. The live capture showed those were caused by the old rectangular grid scan bounds clipping the screen-space rectangle's inverse-isometric corners, not by a need for additional artwork.
- Expanded CastleLayout.GRID_MIN from (-14,-35) to (-30,-55) and GRID_MAX from (85,70) to (110,90). Updated TerrainConfiguration ground_min/ground_max to match. The existing covers_screen_rect filter still limits visible tiles to the authored screen-space bounds, so this adds coverage without changing the garden footprint or gameplay paths.
- Rebuilt baked terrain: 7,488 ground cells, 213 sparse variations, 133 paths, 12 water cells, 6 flower markers. Baked-layer validator PASS with all eight layers and the 32x32 isometric projection unchanged.
- Added explicit smoke assertions for all four portrait screen corners: grid (-28,-13), (10,-50), (67,82), and (105,45), in addition to the existing southeast and portrait top/bottom checks. Main component smoke PASS.
- Fresh live portrait capture: artifacts/qa/royal_gardens_portrait_full_ground_coverage.png. The grass now reaches all four viewport corners; the former clear-color wedges are gone. This is a static portrait screenshot, not a full mobile-device interaction test.
- Godot editor scan after the final grid/bake change completed with exit 0 and no scene parse errors. Live touch movement recheck passed 4/4 cardinal directions with zero collisions.
- Latest backup files include castle_layout.gd.pre_portrait_corner_fill_20261119.bak, castle_terrain_configuration.tscn.pre_portrait_corner_fill_20261119.bak, and castle_garden_component_smoke.gd.pre_portrait_corner_fill_20261119.bak.


## Camera edge coverage and portrait offset clamping (2026-11-19)

- Added a new multi-aspect camera-edge QA that instantiates the real Royal Gardens scene inside 1280x720 landscape, 480x860 portrait, and 720x720 square SubViewports. It teleports the player near all four authored map corners and samples all four viewport corners against the live baked BaseGround TileMapLayer.
- The first run exposed a real issue: Camera2D applies its offset after edge clamping. With the portrait +1000 vertical framing offset, the viewport could extend beyond the bottom ground boundary when the player approached the southern map edge. Landscape also sampled a tile diamond just outside the old ground edge at the north boundary.
- Added CastleLayout.CAMERA_EDGE_PADDING = (64,64) and inset the camera's base world bounds from the baked ground rectangle by one 64x32 tile safety margin.
- Added PlayerCameraRig.set_world_bounds() and dynamic vertical limit compensation. Each time the follow offset eases, the camera top/bottom limits shift by the inverse current offset, keeping the rendered viewport edge inside the ground even during portrait transitions and vertical look-ahead.
- Updated CastlePlayerSpawnerComponent to use the inset bounds and the new camera API. Player movement, terrain, paths, collision and art placements remain unchanged.
- New camera edge coverage result: landscape 16/16 viewport corners covered; portrait 16/16; square 16/16. Tested at four near-boundary player positions per aspect. The previous failing samples are now covered.
- Updated the main component smoke test to assert the inset world limits: (-1103,-883) to (2647,2758) at the current authored world transform. Main smoke PASS; camera aspect QA PASS; baked-layer validator PASS (7,488 ground cells, 213 variations, 133 paths, 12 water, 6 flowers, 8 layers).
- This is a geometry/TileMap coverage test; it complements rather than replaces live renderer screenshots and a manual walk-through.
