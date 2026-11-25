# Reverie Act I — Tilemap Foundation

## Core files
- scenes/world/act1_tilemap_foundation.tscn: six-region node-based TileMapLayer foundation.
- scenes/world/components/royal_gate_architecture.tscn: modular Royal Gate entrance composition and collision.
- scenes/world/components/royal_gate_architecture_preview.tscn: isolated visual preview of the gate composition.
- assets/environment/act1_generated_tiles/generated_grass_32.png: Pixel Engine-generated grass tile (32×32).
- assets/environment/act1_generated_tiles/act1_generated_grass_isometric_tileset.tres: generated grass tile registered on the project's 64×32 isometric logical grid.
- tests/act1_tilemap_foundation_smoke.gd: structural validator.
- tests/royal_gate_collision_smoke.tscn and .gd: player-vs-gate physics test.

## Region order
Royal Gardens → Royal Gate → Willow Fields → Elderwood Grove → Forsaken Ruins → Ruined Tower.

## Per-region layers
Each region has a generated-grass candidate TileMapLayer, ground blending, paths, water, vegetation, foreground, collision authoring group, and entry/exit markers. The generated tile candidate is hidden by default. The visible terrain continues to use the established isometric ground atlas, avoiding the dark square seams visible when the generated grass tile is repeated. Royal Gardens also retains its existing validated editor-baked ground and path layers.

All regions use the established 64×32 logical isometric coordinate system and 32×32 atlas art regions.

## Royal Gate composition
The Royal Gate region instances a dedicated node-based architecture scene using existing authored production PNGs:
- Main ornate entrance gate
- Left and right wall segments
- Mirrored corner towers
- Paired royal banners
- Paired entrance lanterns
- Flowering shrub accents

The scene includes an editable ApproachPath TileMapLayer using the established path/water TileSet, plus gate-threshold and arrival markers. The approach path is intentionally unpainted until its exact footprint is reviewed in the TileMap editor.

### Paint palette and layout target
Use the existing authored atlases first; do not replace them with generated square grass or runtime drawing. Atlas coordinates below are (column, row) in the 4×4 32 px source grid.

- Ground base: (0,0), (1,0), (0,1) for the main lawn; (2,0) and (3,1) for restrained darker variation.
- Ground transitions: (0,2) and (2,2) to soften the lawn-to-earth/paving edges; (1,2) and (0,3) only for small worn-earth patches.
- Approach paving: path atlas (0,0), (1,0), (2,0), (3,0) for the cobble run; use (0,1) and (1,1) sparingly as ornamental threshold accents.
- Water atlas tiles (0,2) through (3,3) are reserved for a later fountain/pool treatment; do not scatter water tiles through the walking corridor.

Composition target: a centered 3-cell-wide stone approach leading to the 160 px gate opening, widening into a compact forecourt just inside the gate. Keep grass shoulders on both sides, with small irregular earth/grass transitions rather than a hard rectangular border. Preserve a clear walkable centerline from the western entry marker to the eastern exit marker. The fountain, statues, bench and shrubs remain outside that corridor.

The 32×32 art regions sit on the existing 64×32 logical isometric grid (screen deltas +32,+16 and -32,+16). Paint and inspect at the actual gameplay camera scale; do not stretch the atlas or scale the TileMapLayer to hide seams.

The gate forecourt now has additional hand-placed production art: paired guardian statues, paired wisteria trees, a tiered fountain on the left side, a garden bench on the right, and violet shrub accents. These details sit outside the central approach corridor so they do not visually close the entrance. The existing gate, wall, tower, banner, lantern, and pink-flower pieces remain separate Sprite2D nodes for later repositioning.

## Royal Gate collision pass
Four StaticBody2D blockers now define the wall line on world collision layer 1:
- Left wall blocker: 120×20 px
- Left gate pier blocker: 50×20 px
- Right gate pier blocker: 50×20 px
- Right wall blocker: 120×20 px

The central opening remains 160 px wide, so the 18 px player capsule can pass through. The blockers are placed at the grounded base line of the decorative wall art. Their geometry is intentionally separate from the sprites so later art adjustments do not silently alter collision.

The eight forecourt props also have separate world-layer StaticBody2D blockers: two guardian statues, two wisteria trunks, the fountain base, the bench footprint, and two violet shrubs. Their collision footprints are deliberately compact and sit at the ground-contact points, leaving the center approach open.

## Validation
- ACT1_TILEMAP_FOUNDATION_PASS: six regions, assigned isometric TileSets, hidden generated-grass candidates, modular gate architecture, eight forecourt art props, four wall blockers, and eight prop blockers. The validator also checks both 128×128 atlas textures, their 32×32 regions, all sixteen atlas entries, the 64×32 diamond grid, and that Royal Gate ApproachPath remains empty for manual painting.
- ROYAL_GATE_COLLISION_PASS: the actual Player scene is blocked by both left and right gate piers and the side fountain base, while still moving through the central opening.
- PLAYER_ENVIRONMENT_COLLISION_PASS: all eleven authored palace/perimeter blockers stop the player, while the grand front gate remains traversable.
- ROYAL_GARDENS_GAMEPLAY_PASS: the 194-cell authored route is connected, the promenade remains clear, fountain bases block movement, and the clean garden composition remains intact.
- POND_LOCOMOTION_PASS: west/east shoreline routes are physically traversable without entering water; water speed reduction and dry-ground recovery both work.
- ACT1_AREA_CONTENT_PASS: all five non-garden Act I area scenes retain their landmark, editable PixelPen archive, and NPC dialogue content.

The collision test exercises the Player CharacterBody2D against the instantiated gate StaticBody2D nodes in Godot physics. It does not yet certify collision alignment against every decorative tower/flower pixel, nor replace a full in-game visual playtest.

## Status and next pass
This is a structural and collision foundation, not a finished painted map. The new generated grass asset is imported, assigned as a hidden candidate in all six regions, and retained for refinement. The visible ground uses the established isometric atlas. Royal Gate modular architecture and the player-sized passage are mounted and physics-tested. No runtime/procedural terrain generation is used. The existing live Royal Gardens renderer and multiplayer systems are untouched.

Next production milestone: paint the Royal Gate approach and forecourt directly in the Godot TileMap editor using the existing ground and path/water atlases and the palette/layout target above. Keep the generated-grass candidate hidden; it is not a prerequisite for the hand-authored route. After painting, inspect the passage at gameplay camera scale, verify the centerline remains open around all eight prop blockers, and only then continue into Willow Fields. Do not generate TileMap cell placements with runtime code or scripts.
