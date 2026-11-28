# Reverie — Start here

Open `project.godot` in Godot 4.7.2. Use this index instead of browsing the entire project tree.

## What to edit

| Task | Location |
| --- | --- |
| Maps and zone layouts | `scenes/world/six_zone_reverie/individual_zones/` |
| Map assets | `assets/world/`, `assets/environment/` |
| World interactions and navigation | `scripts/world/` |
| Character sprites and animations | `assets/characters/`, `scenes/characters/` |
| Character portraits and banners | `assets/portraits/` |
| Combat and battle presentation | `scripts/combat/`, `scenes/combat/`, `scripts/ui/combat/`, `assets/combat/` |
| Summoning and collection | `scripts/gacha/`, `scripts/collection/`, `scripts/ui/screens/gacha_screen.gd` |
| Character, skill, banner and dialogue definitions | `resources/data/` |
| Story cinematics and soundtrack | `assets/cinematics/`, `assets/audio/` |
| UI and menus | `scenes/ui/`, `scripts/ui/` |
| Online services and live content | `backend/api/`, `scripts/online/` |
| Source artwork and design references | `art_source/`, `documentation/art_reference/` |
| Tests and QA utilities | `tests/`, `tools/` |
| Documentation | `docs/`, `documentation/`, `README.md` |

## Main playable maps

In Godot, open the following scenes inside `scenes/world/six_zone_reverie/individual_zones/`. The legacy file names are intentional: renaming them risks breaking scene references, transfers and saved progression.

- Village: `zone_00_village_standalone.tscn`
- Zone 1: `zone_01_royal_gardens_standalone.tscn`
- Zone 2: `zone_02_royal_gate_standalone.tscn`
- Zone 3: `zone_03_willow_fields_standalone.tscn`
- Zone 4: `zone_04_elderwood_grove_standalone.tscn`
- Zone 5: `zone_05_forsaken_ruins_standalone.tscn`
- Zone 6: `zone_06_ruined_tower_standalone.tscn`

For the authoritative online zone mapping, see `resources/data/six_zone_expeditions.json`. Draft, review and background-reference scenes are not interchangeable with the playable maps.

## Local working files

- `exports/`: builds and the current signed Android release; keep the preset paths intact.
- `build/`: generated build output.
- `artifacts/`: historical tracked reports and local QA output. It is not a runtime asset folder.
- `backups/`: local rollback snapshots, not for Git.
- `outputs/`: local development output.
- `.godot/`: generated editor/import cache. Do not edit manually.

On the development PC, archived files live in the sibling folder `Reverie Archive/`, outside the Godot project. Each cleanup folder contains a `manifest.csv` with original relative paths and byte sizes. Restore an individual file by copying it back to its original path only after checking that it will not overwrite newer work. Historical QA references in older documentation may point to files in this archive.

Keep new logs, screenshots and backups out of the project root. Put QA output in `artifacts/qa/` or an external archive, and keep only authored project resources in the runtime directories. Do not move or delete active scenes, artwork, resource UIDs, import settings, save data, backend secrets or signing files as part of a general cleanup.

Before publishing: run the relevant Godot and backend tests, review the staged diff, then confirm GitHub CI.
