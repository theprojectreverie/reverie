REVERIE — ROYAL GARDEN ASSET PACK v1

59 individually extracted transparent PNG sprites.
- sprites/tiles: 9 ground and path pieces
- sprites/structures: 24 arches, hedges, gates, fountains, ponds, benches and structures
- sprites/props: 2 lamps and decorative props
- sprites/flora: 24 flowers, topiary, planters, urns, foliage and rock clusters

All sprite canvases are aligned to 32px grid units. Larger props use 64x64 or 96x96 canvases as listed in manifest.json.
PNG alpha is preserved. Preview_contact_sheet.png is a preview only; its checkerboard is not part of the sprites.
Godot imports are lossless with mipmaps disabled. Project default texture filtering is nearest-neighbour.

INTEGRATION STATUS
Nine textures have been installed at their existing Royal_Gardens resource paths:
- lamp_post_gold <- lamp_ornate
- bench_stone_x <- bench_stone_rose
- fountain_small_1x1 <- fountain_small
- banner_royal_01 <- royal_banner
- flower_pot_01 <- planter_rose
- rose_bush_01 <- flower_cluster_rose
- hedge_corner_1x1 <- hedge_corner
- hedge_x_2x1 <- hedge_straight
- tree_topiary_cone <- topiary_cypress

Their corresponding PackedScene Sprite2D anchors were updated and validated.
Original replaced PNGs and scene files are backed up outside the project at:
Documents/Reverie_Backups/royal_garden_asset_replacements_20261119

No collision geometry, grid footprints, quest logic, or route layout was changed.
The new art remains modular and editable in Godot scenes.
