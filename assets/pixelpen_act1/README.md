# Reverie — Act I PixelPen Asset Pack

These original landmark sprites were authored as indexed-color PixelPen projects inside the Godot addon at `addons/net.yarvis.pixel_pen`.

Each landmark has:
- A native `.pxpen` source project (64×64, editable palette/indexed layer).
- A transparent `.png` export used by the in-game landmark scene.
- A dedicated landmark scene, positioned at its region's authored POI grid coordinate.

The five new regions also include talkable named NPCs with original dialogue entries in `resources/data/dialogue.json`. Their POI positions, roles, portraits and palette data live in `resources/data/regions.json`.

## Assets

| Area | PixelPen source | Runtime texture |
|---|---|---|
| Royal Gate | `royal_gate.pxpen` | `royal_gate.png` |
| Willow Fields | `willow_windmill.pxpen` | `willow_windmill.png` |
| Elderwood Grove | `elderwood_ancient_tree.pxpen` | `elderwood_ancient_tree.png` |
| Forsaken Ruins | `forsaken_ruins_arch.pxpen` | `forsaken_ruins_arch.png` |
| Ruined Tower | `ruined_tower.pxpen` | `ruined_tower.png` |

The PNGs are referenced by the five scenes in `scenes/world/act1_areas/`. Keep the PNG and its matching PixelPen project together when editing or replacing a landmark.
