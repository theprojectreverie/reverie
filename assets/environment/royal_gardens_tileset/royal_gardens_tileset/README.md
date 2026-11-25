# Reverie — Zone 01: Royal Gardens

Included:
- `royal_gardens_tileset_sheet.png` — generated RGBA sprite-sheet concept, 1536×1024.

The sheet contains garden ground variants, pale royal paving, water/pond pieces,
hedges, decorative walls, arches, pillars, railings, banners, trees, shrubs,
flower clusters, fountains, statues, benches, planters, and lanterns.

Important integration note:
This is a visual sprite sheet, not yet a production-ready Godot TileSet atlas.
Individual sprite bounds and tile origins have not been manually sliced or
validated. Import it as a texture first; create individual Sprite2D/TextureRect
regions or an AtlasTexture/TileSet only after checking each sprite's exact
rectangle and pivot in Godot. Do not assign arbitrary 32×32 atlas cells: many
structures and props are multi-tile objects.

Suggested project destination:
`res://assets/environment/royal_gardens_tileset/`

Color/alpha:
RGBA PNG. Very low-alpha background haze was removed; antialiased sprite edges
were retained.
