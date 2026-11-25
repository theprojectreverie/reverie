# Royal Gate Zone 02 — Path alignment QA

## Verified corrections (21 November 2026)
- Central stone avenue uses native `garden_stone_path.tscn` tiles, each 64×32 px.
- Diagonal crossing also uses the same native tile scene, with no PNG manipulation.
- Prior to correction, the two road systems occupied offset isometric lattices, yielding zero identical tile origins across their crossing.
- `royal_gate_diagonal_crossing.tscn` root was moved `Vector2(-16, -2)` so its nodes share the actual central avenue lattice. Audited identical origins at the intersection increased to 72. This is a scene-node transform, not a script-driven visual.
- Backed up previous diagonal crossing as `royal_gate_diagonal_crossing.tscn.before_tile_grid_alignment`.
- The standalone Royal Gate scene passed the Godot 4.7.2 headless loading test.
- The previous lavender corner and grass end-cap accents failed visual suitability tests because of visible raised edges and mismatched stone tint. They remain excluded from `zone_02_royal_gate.tscn`; imported candidate textures remain available for review but are not deployed.

## Remaining acceptance tests
1. Inspect road intersection at gameplay zoom and validate outer/inner silhouette corners. Repeating diamond borders still have visible serrations; this is not yet approved for final art.
2. Replace failed lavender decorative edge sprites with artist-designed peach stone compatible with the native road; verify real alpha and 64×32 footprint.
3. Inspect joins into both standalone zone transfer roads without relocating transfer markers.
4. Do not add collision until specifically requested; keep map art as Godot nodes/scenes.

## Review-only scenes
- `royal_gate_visual_review.tscn`: full map.
- `royal_gate_edge_join_closeup_review.tscn`: central avenue and diagonal crossing, no rejected accent nodes.
- `royal_gate_transfer_joins_visual_review.tscn`: shared full zone with the native entry/exit connectors; review camera can be adjusted in the editor.
- `royal_gate_entry_join_inspection.tscn`: inherited, editor-authored close-up scene centered on the entrance join.
- `royal_gate_exit_join_inspection.tscn`: inherited, editor-authored close-up scene centered on the exit join.
- Both close-up inspection scenes passed Godot 4.7.2 loading tests on 21 November 2026. Their seams remain visually unapproved pending an unobstructed close-up inspection.


## Native transfer-road connector update (21 November 2026)
- The standalone Zone 02 entrance and exit segments were disconnected from the zone road artwork by native-tile pixel-mask comparison.
- Added reusable editor-authored `royal_gate_transfer_road_connectors.tscn`: two instances of existing `stone_road_6x10.tscn` continuing the entrance and eight instances of existing `garden_stone_path.tscn` for the entrance/exit seams.
- Instanced it as `NativeTransferRoadConnectors` in `zone_02_royal_gate_standalone.tscn` after backing up the original as `zone_02_royal_gate_standalone.tscn.before_transfer_path_connectors`.
- Pixel-mask audit verified the entry connector overlaps both the old entry road (939 pixels) and central zone avenue (244 pixels), and the exit connector overlaps the exit road (1,298 pixels) and joins the core diagonal road (77 pixels of 1px-expanded contact). These are technical connectivity metrics, not final visual approval.
- Removed nested negative z_index from the diagonal crossing wrapper (backup `royal_gate_diagonal_crossing.tscn.before_z_order_fix`), retaining the native `RoadTiles` layer at z=-19 above grass z=-20.
- Godot 4.7.2 standalone scene loading test passed with exit code 0.
- Verified both transfer marker nodes and their Area2D triggers exactly match the backed-up scene. No collision shapes, collision settings, or draw scripts added.

### Still to inspect
- Side entrance/exit seams in a fresh unobstructed game view, especially subtle mismatched tile origin offsets and path-width changes.
- The junction's jagged silhouette remains a separate art polish item. Never approve unmatched lavender curb sprites merely because tile origins align.

## Exit bridge correctness fix (21 November 2026)
- Re-audited visual continuity using the true 60 Stone_ tiles in stone_road_6x10.tscn; the prior 61st coordinate was its TransitionEnd marker, NOT artwork.
- The previous six-tile exit seam produced two disconnected foreground pixel regions (65,018 and 64,080 pixels) in the cropped junction audit; one-pixel dilated proximity alone was insufficient evidence of continuity.
- Added an editor-authored, reusable royal_gate_exit_native_bridge.tscn with 19 individually positioned, existing garden_stone_path scene instances. No generated artwork, drawing scripts, or collisions.
- Compared bridge and old six seam tiles side by side. The redundant old six tiles created darker doubled joins, so they were removed from royal_gate_transfer_road_connectors.tscn (backups: .before_native_exit_bridge and .before_exit_old_seams_removal).
- New bridge without old seam pieces yields one connected visible foreground region of 142,632 pixels in the cropped 8-connected-components audit; previous six seams had two disconnected regions.
- Scene references and both transfer markers/triggers were checked unchanged against backups. Godot 4.7.2 standalone load validation passed.
- This is geometric road connectivity, NOT final visual approval: path's outside zigzag and replacement decorative curb artwork still need artist review.


## Entrance transition polish — 21 November 2026
- Rechecked the entry seam with a full pixel-mask 8-connected-component test: native road + its two continuation sections form one connected region, and the core avenue forms another without seam tiles. Entry seam joins these into a single connected foreground region.
- Compared 2-, 4-, 6-, and multi-tile seam variants against actual garden_stone_path texture; selected 4 editor-authored existing stone tile instances, retaining spacious road width without spreading a dense decorative pavement block.
- Added EntrySeamOuterLeft at (242,636) and EntrySeamOuterRight at (338,668) in the reusable transfer connector scene (backup .before_entry_seam_widen).
- Godot 4.7.2 standalone load and transfer marker/trigger invariance checks passed. No collisions or code-generated drawing added.
- Both entrance and exit outer edges still await artist approval; existing candidate decorative corners were rejected and remain uninstalled.


## Native entrance road lattice alignment — 21 November 2026
- Found an exact coordinate-lattice mismatch: central zone road tile origins were x modulo 32 = 18 and y modulo 16 = 12; the original standalone entry road and its two editor-instanced continuations were x modulo 32 = 23 and y modulo 16 = 8.
- Compared unaltered and snapped variants against the existing peach-stone texture at magnified pixel-art resolution; corrected entrance section transforms by (-5,+4) pixels while leaving the existing seam tiles in their correct positions.
- EntryRoadFromZone01 in zone_02_royal_gate_standalone.tscn is now (-430,124). EntryContinuation01=(-110,284), EntryContinuation02=(210,444) in royal_gate_transfer_road_connectors.tscn.
- Both scene files were backed up with .before_entry_lattice_snap suffix.
- Godot 4.7.2 loading test passed; metadata, transfer markers, and their trigger nodes remain unchanged. No collision or generated visual art.
- Decorative curb / sharp road-edge polish still remains unapproved.


## Junction inside-corner refinement — 21 November 2026
- Compared four before/after editor-tile arrangements at the crossing of CentralStoneAvenue and DiagonalCrossing, using the real native stone texture.
- Selected a minimal two-tile infill at the concave west/east junction edges; four-tile alternatives introduced awkward protrusions, so rejected.
- Created editor-authored royal_gate_junction_infill.tscn containing two instances of the existing garden_stone_path tile scene, at Zone 02-local coordinates (-208,1726) and (208,1902), whose standalone-world coordinates are (-78,1644) and (338,1820). These share the exact native 64x32 road lattice.
- Instanced JunctionCornerInfill in zone_02_royal_gate.tscn. Backed up original as zone_02_royal_gate.tscn.before_junction_corner_infill.
- Godot 4.7.2 standalone loading passed. Node positions, lattice, no-collision and no-drawing-script checks passed.
- The decorative/path-boundary sprites rejected previously remain excluded. This infill is a native-stone geometry polish, not approval of final decorative curbs or the whole zone.

## Full Zone 02 stone-road topology verification — 22 November 2026
- Reconstructed the actual scene-node positions of central avenue, crossing, inner-corner infill, transfer road pieces, native exit bridge, and remaining entry seam tiles.
- Raster-alpha topology test of 64×32 stone artwork over the complete scene: **one connected foreground region, zero enclosed holes**.
- Every native road tile is on the same x modulo 32 = 18, y modulo 16 = 12 lattice except the original exit-road instance, which the dedicated editor-authored native bridge connects without moving transfer markers.
- Identified and removed two exact duplicate entry seam Sprite/PackedScene node instances at (306,652) and (338,668). Both are already rendered by EntryContinuation02. Connector scene backed up as .before_seam_duplicate_cleanup.
- Full road connectivity remains one component with no holes and unchanged 1,575,992 opaque stone pixels. Godot 4.7.2 loads successfully. Transfer marker and Area2D trigger content unchanged.
- An additional 72 duplicated tile origins occur where the central avenue and diagonal crossing overlap; left unchanged pending separate optimization of reusable editor scenes.
- This is a technical structural check, not final artwork approval. Decorative corners and road-edge silhouette still need review; no new collisions or code-drawn artwork.

## Crossing duplicate removal — 22 November 2026
- The original diagonal crossing had 72 exact same-position instances as the central avenue: 45 in CrossingSegment05 and 27 in CrossingSegment06.
- Replaced those two fully/partially redundant 60-tile section instances with reusable editor-native royal_gate_crossing_midsection_unique.tscn containing the 48 non-duplicated instances of the same existing garden_stone_path scene.
- The other seven crossing segments remain reusable native stone_road_6x10 scene instances. The original royal_gate_diagonal_crossing.tscn was backed up as .before_duplicate_road_cleanup.
- Exact world-space tile-origin set comparison verified every original road coordinate remains covered by the same stone artwork, removing precisely 72 duplicated tile scene instances without changing any visible road area.
- Updated the complete-zone road topology audit to account for the new uniquely instanced midsection: diagonal tiles 468 (was 540); full road network remains 1 foreground component, 0 enclosed holes, 1,575,992 opaque stone pixels.
- Godot 4.7.2 standalone scene loaded successfully. No collision added, no generated art, no new runtime scripts. Decorative road-edge art is still pending visual approval.

## Real Godot renderer clearance review — 22 November 2026
- Used a temporary diagnostic scene capture (real Godot 4.7.2 framebuffer, not a conceptual contact sheet) to inspect the current Zone 02 art layout. Before the fix, LeftTree was visibly overlapping the diagonal road and a right flowerbed overlapped its surface.
- Exact per-pixel alpha-mask testing of art sprites against the existing editor-authored stone road confirmed LeftTree 5,541 overlapping opaque pixels, RightFlowerbedUpper 4,109, and RightFlowerbedLower 307; the other examined small decorative sprites had no road overlap.
- Updated reusable royal_gate_art_layout.tscn, backed up as .before_road_clearance_polish. Both purple trees moved symmetrically from x +/-680,y1440 to y1100; upper flowerbeds to x +/-460,y1750; lower flowerbeds to x +/-340,y2250.
- Re-ran sprite-alpha road clearance audit: all ten lantern, topiary, tree, and flowerbed nodes now have zero overlapping pixels AND zero sprite pixels within a 7-pixel expanded boundary of Zone 02's native roads. SingleRoyalGate gateway is intentionally excluded from this local clearance mask.
- Captured a second actual Godot renderer screenshot at C:/Users/quoth/Downloads/royal_gate_actual_full_map_render.png. It shows both trees and both pairs of flowerbeds standing on grass and the diagonal crossing clear of those props.
- Confirmed the standalone Zone 02 scene loads in Godot 4.7.2 with exit code 0. No collisions added, no new runtime artwork scripts, no transfer markers moved, and the other five zones left untouched.
- Separately rendered the rejected lavender 64x40 border atop the native pink-peach 64x32 paving via an editor-authored QA scene. Its color, thickness, and footprint remain incompatible. It has NOT been deployed in gameplay. Matching hand-designed borders still need approval.

## North Gate approach and transfer-path verification — 22 November 2026
- Real Godot OpenGL framebuffer close-up exposed a grass gap separating the front of the royal gate artwork from the start of the central stone avenue. The stone end was visually disconnected from the gate entrance.
- Tested a native 6x10 stone-road extension at local Zone 02 position (0,590), corresponding to standalone world root (130,508), with parent rendering layer z=-19 so the gate artwork remains in front. Without z=-19 the stones incorrectly drew across and concealed the lower front of the gate; that visual test was rejected.
- Deployed GateApproachSection in royal_gate_central_avenue.tscn and backed up the prior avenue scene as .before_gate_approach_extension. Review capture now shows continuous paved ground from the royal gate down into the main avenue, without covering the gate facade.
- Found 30 redundant tile instances between the extension and EntryContinuation02. Replaced the 60-tile gate approach with an editor-authored reuse scene royal_gate_gate_approach_unique.tscn containing precisely the 30 still-visible nonduplicate existing native stone tiles. The avenue scene is backed up again as .before_unique_approach. Proven exact same tile-origin coverage as the earlier full extension, no new art or collision.
- Final complete road audit: 870 avenue tile positions, 468 diagonal positions; entire standalone road network one connected raster-alpha component, 0 enclosed holes, 1,605,348 opaque stone pixels. Both unchanged transfer markers (-521,200) and (1664,2432) lie on native stone tiles; their Area2D trigger scene text remains unchanged.
- Exact Godot-rendered QA screenshots created in Downloads: royal_gate_full_standalone_join_render.png and royal_gate_approach_extension_closeup.png. All presentation uses reusable native PackedScene nodes; no new runtime drawing scripts. The temporary capture script is a QA tool and must be archived outside Godot after use.
- Remaining: replacement artist-designed gold/peach stone edge and corner sprites with verified alpha and native diamond geometry, gameplay zoom polish, and optional later movement/collision test when user authorizes. Do not approve unreconciled lavender border pack.

## Standalone player arrival QA — 22 November 2026
- Actual Godot 4.7.2 camera render uncovered a gameplay-breaking spawn error: opening Zone 02 positioned Kael at (-521,380), which was **outside the grass/stone diamond**, leaving nearly the entire viewport black. The original generic vertical +/-180 offset from the transfer marker did not follow a diagonal isometric road.
- Backed up zone_02_royal_gate_standalone.tscn and standalone_zone_controller.gd as .before_safe_spawn_markers. Authored two **Marker2D** spawn anchors in Zone 02: SafeSpawnFromPreviousZone at (0,900), SafeSpawnFromNextZone at (1100,2000). Both coordinates were individually verified against the actual stone-road alpha footprint.
- Existing shared standalone controller checks optional editor-authored arrival markers after its legacy offset. Other five zone scenes contain no such markers and therefore retain their former logic; no code-generated visible art was added.
- Two actual Godot GPU framebuffer screenshots verified Kael on the paving with local landscape visible: Downloads/royal_gate_actual_player_camera.png (starting/Zone 01 arrival) and Downloads/royal_gate_from_willow_player_camera.png (Zone 03 return arrival). Player's Camera2D follows and the whole diamond is not shown at once.
- Repeated exact-scene comparison against saved snapshot confirms existing ToPreviousZone/ToNextZone marker nodes, transfer triggers, destination metadata and CollisionShape2D nodes are **identical to before**. No collision authored or moved.
- The new anchors solve the off-map arrival issue. Final road-edge and native peach-stone corner art remain unresolved, so **Royal Gate is not fully art-approved**.

## Live Zone 02 transfer behavior — 23 November 2026
- Executed Godot 4.7.2 runtime physics tests by instantiating each source zone and placing the player body inside the existing transfer Area2D, across four directions.
- Zone 02 to Zone 03: StandaloneZone03 loaded, player spawned at (-2540,1440), passed.
- Zone 02 to Zone 01: StandaloneZone01 loaded, player spawned at (1576,2200), passed.
- Zone 03 to Zone 02: StandaloneZone02 loaded, player spawned at SafeSpawnFromNextZone (1100,2000), passed.
- Zone 01 to Zone 02: StandaloneZone02 loaded, player spawned at SafeSpawnFromPreviousZone (0,900), passed.
- No collision nodes, transfer targets, or cross-zone artwork were edited. The safe-spawn marker fallback remains optional for other zones. Actual Godot screenshots confirmed Kael and terrain in both Zone 02 arrival views.
- Visual border and corner acceptance remains pending.

## Return-transfer bounce-back regression — 23 November 2026
- Simulated the two Zone 02 arrival conditions in Godot physics for 180 frames each (~3 sec at 60 physics FPS), with the player remaining motionless at the newly authored safe spawn positions.
- Willow Fields -> Royal Gate: SafeSpawnFromNextZone at (1100,2000), remained StandaloneZone02 for all 180 frames; no automatic bounce to Zone 03.
- Royal Gardens -> Royal Gate: SafeSpawnFromPreviousZone at (0,900), remained StandaloneZone02 for all 180 frames; no bounce to Zone 01.
- Previous four-direction live transfer tests all passed, including both outward Zone 02 transfers. No transfer targets or collision settings were changed.

## Exit transition road-edge refinement — 23 November 2026
- Compared four candidate infill configurations against the authentic 64x32 peach native stone tile at actual tile origins, then selected a restrained 5-tile approach and one additional lower-left neck infill.
- Updated reusable editor-authored royal_gate_exit_native_bridge.tscn from 19 to 25 individually placed native stone nodes: (1426,2300), (1394,2316), (1426,2332), (1522,2252), (1586,2252), and (1458,2348). Backups: .before_exit_edge_refinement and .before_exit_neck_widen.
- Captured and inspected a fresh genuine Godot 4.7.2 render at the exit seam: Downloads/royal_gate_exit_join_refined_actual.png. The upper/right notch and narrow west corner are visibly less pronounced. Path edges still have a pixel-grid zigzag and exit grass boundary remains exposed to the black outer background, pending matching artistic edge sprites.
- Verified all 25 native tile origins unique and lattice-aligned, alpha-raster road remains a single connected foreground with no meaningful enclosed holes. No new collision, runtime artwork scripts, or changes to the transfer targets.
- Searched existing PNG assets for color-compatible hand-designed paving edges. Closest extracted candidates are raised stone slabs, differently sized and with mattes; they are not safe 64x32 replacements. Keep them rejected. A new candidate generated during design exploration was an RGB image with white background and was not imported into Godot; it fails transparency and tile-footprint acceptance requirements.
