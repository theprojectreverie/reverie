# Act I — The Royal Road

This progression follows the visual reference from the Royal Gardens into the countryside, ancient woodland and corrupted ruins.

## Playable route

1. **Royal Gardens** — existing handcrafted estate; now connects to the Royal Gate.
2. **Royal Gate** — arrival checkpoint and Road Warden Elowen.
3. **Willow Fields** — pastoral valley, PixelPen windmill landmark and Miller Ada.
4. **Elderwood Grove** — moonlit ancient woodland, PixelPen elder tree and Grove Keeper Thalen.
5. **Forsaken Ruins** — broken royal aqueduct, corrupted arch and Scout Merrow.
6. **Ruined Tower** — violet spire, Moon Shard shrine and Tower Sentinel.
7. **Gothic Castle** — existing sealed keep / boss destination.

## Implementation

- Region definitions, POIs, biomes, spawns, map origins, entry points and reciprocal travel connections: `resources/data/regions.json`.
- NPC dialogue: `resources/data/dialogue.json`.
- World composition, NPC creation, interactives, lighting and portal spawning: `scripts/world/components/world_region_builder_component.gd`.
- Region scene routing: `scripts/game/game_world_session_component.gd`.
- Five dedicated landmark scenes: this folder.
- Editable PixelPen source projects and transparent runtime exports: `assets/pixelpen_act1/`.

All five new regions use the existing streamed GreenwardWorld renderer, while keeping their own noise seeds, palettes, prop ecology, fog, ambient tint, encounters and POI layouts. The static Greenward village is hidden outside the Greenward region. The original castle and Gothic Castle scenes remain separate.

## Verification

Run these from the project root with Godot 4.7.2:

```powershell
Godot_v4.7.2-stable_win64_console.exe --headless --path . --script res://tests/act1_region_graph_smoke.gd
Godot_v4.7.2-stable_win64_console.exe --headless --path . --script res://tests/act1_area_scenes_smoke.gd
Godot_v4.7.2-stable_win64_console.exe --headless --path . res://tests/map_coordinate_smoke.tscn
```
