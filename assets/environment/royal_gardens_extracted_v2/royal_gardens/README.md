# Reverie — Royal Gardens extracted asset pack

Contains individually extracted transparent RGBA sprites, the original generated sheet,
a numbered visual catalog, and a JSON manifest with source rectangles.

IMPORTANT:
- Sprites are extracted from image artwork by transparency-based segmentation.
- Some adjacent artwork is connected and remains grouped in one PNG.
- Individual images have differing sizes; they are NOT a validated 64×32
  Godot TileSet atlas. In particular, ground diamonds are larger than 64×32.
- Use decorative objects as Sprite2D scenes with editor-set origins.
- Ground tiles must be redrawn or manually rescaled/reworked and seam-tested
  before filling the existing 64×32 grid.
- The sheet's faint semitransparent background has been removed from
  extracted sprites using an alpha threshold and component masks.
- Inspect sprite_catalog.jpg before placing the assets.

This package does not modify the Godot project.
