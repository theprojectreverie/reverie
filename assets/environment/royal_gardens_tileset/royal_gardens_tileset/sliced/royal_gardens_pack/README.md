# Royal Gardens — sliced asset pack

Transparent RGBA PNG sprite crops, segmented from the generated 1536×1024 source sheet using connected alpha regions.

Folders: ground tiles, stone paving/borders, hedges/edges, water/fountains, architecture/fences, trees/plants, flower clusters/details. See ASSET_MANIFEST.json for exact dimensions and categories.

The original sheet contains overlapping decorative compositions and disconnected small ornaments. Crops are separated by connected visible regions; some architectural/hedge crops are multi-part prefabs rather than single ground tiles. Inspect pivots and tile footprints before use in Godot. Ground crops are the candidates for zone floor replacement; do not auto-tile all props.
