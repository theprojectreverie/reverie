REVERIE ACT I — ROYAL ROAD

The live authored route follows a seven-area progression:
1. Royal Gardens — existing authored garden world.
2. Royal Gate — existing garden exit and road threshold.
3. Willow Fields — calm pastoral roadside landmark assembly.
4. Elderwood Grove — old woodland with the first visible corruption.
5. Forsaken Ruins — broken processional arch and fallen stonework.
6. Ruined Tower — final approach and violet spire.
7. Gothic Castle — sealed keep and Baltoria arena.

LIVE ACT I ROUTE
- The playable progression is now a chain of regions: Royal Gardens -> Royal Gate -> Willow Fields -> Elderwood Grove -> Forsaken Ruins -> Ruined Tower -> Gothic Castle.
- The five new intermediate regions use the existing streamed GreenwardWorld runtime with distinct biome palettes, prop weights, POIs, encounter groups, entry points and reciprocal travel gates.
- Their authored landmark assemblies live in scenes/world/act1_areas/ and use original PixelPen PNG exports.
- Editable PixelPen source projects and runtime PNGs are stored together in assets/pixelpen_act1/.
- The original 40-tile road and roadside dressing in royal_road_to_baltoria.tscn remain preserved as the Gothic Castle route composition.

REUSABLE ROAD PROTOTYPES
The four 3x3 segment scenes remain authoring prototypes:
- royal_stone_segment
- fading_stone_segment
- corrupted_stone_segment
- ruined_tower_approach_segment

Do not instance these prototypes over the live 40-tile road without first replacing the corresponding tiles; that would double the ground.
