# Reverie — Tutorial Asset Pack (Draft 01)

This pack contains extracted sprite crops for the dedicated tutorial map:
- Kael's bedroom and house interior
- The adjoining garden/training courtyard
- Ground textures exported at exactly 32x32 pixels

## Folders
- `Bedroom/` — furniture, interior architecture, doors, rugs and décor
- `Training_Ground/` — sparring platform, practice equipment, garden structures and props
- `Tiles_32x32/` — ground tile textures, each exactly 32x32 px
- `Source_Sheets/` — original generated sheets retained for reference
- `asset_manifest.json` — crop names, dimensions and source crop coordinates

## Godot import notes
- Import the PNGs as ordinary `Texture2D` assets.
- The 32x32 tile PNGs are already 32x32 pixels and can be used in a TileSet atlas.
- Furniture and large props intentionally retain larger sprite dimensions; they should occupy multiple 32px grid cells rather than being forced into 32x32.
- This is an extracted draft pack, not yet a fully sliced/QA-approved production tileset. Some crops may need manual boundary cleanup, collision setup, pivots/origins, and final grid-footprint assignment in Godot.
- The bedroom sprite sheet's light background was removed by edge-connected background masking. Inspect pale edges on light-colored sprites before final use.
