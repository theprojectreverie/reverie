# Mossling authored-art source manifest
Date: 2026-11-20

Status: source strips not yet staged. This manifest defines the exact inputs required by the Godot SpriteFrames importer.

## File contract

- One transparent PNG horizontal strip per state/direction.
- Frame canvas: 96 × 128 px; strip height: 128 px.
- Strip width: frame count × 96 px.
- Preserve Mossling's silhouette, palette, proportions, and 8-way facing consistency across states.
- Frames must be genuinely distinct authored poses; do not duplicate, pad, interpolate, or procedurally synthesize missing frames.
- Each PNG goes at `assets/enemies/mossling/animations/<state>/<direction>.png`.

## Required source files

| State | Direction | Frames | Required PNG dimensions |
| idle | down | 5 | 480 × 128 |
| idle | down_right | 5 | 480 × 128 |
| idle | right | 5 | 480 × 128 |
| idle | up_right | 5 | 480 × 128 |
| idle | up | 5 | 480 × 128 |
| idle | up_left | 5 | 480 × 128 |
| idle | left | 5 | 480 × 128 |
| idle | down_left | 5 | 480 × 128 |
| walk | down | 16 | 1536 × 128 |
| walk | down_right | 16 | 1536 × 128 |
| walk | right | 16 | 1536 × 128 |
| walk | up_right | 16 | 1536 × 128 |
| walk | up | 16 | 1536 × 128 |
| walk | up_left | 16 | 1536 × 128 |
| walk | left | 16 | 1536 × 128 |
| walk | down_left | 16 | 1536 × 128 |
| run | down | 16 | 1536 × 128 |
| run | down_right | 16 | 1536 × 128 |
| run | right | 16 | 1536 × 128 |
| run | up_right | 16 | 1536 × 128 |
| run | up | 16 | 1536 × 128 |
| run | up_left | 16 | 1536 × 128 |
| run | left | 16 | 1536 × 128 |
| run | down_left | 16 | 1536 × 128 |
| interact | down | 6 | 576 × 128 |
| interact | down_right | 6 | 576 × 128 |
| interact | right | 6 | 576 × 128 |
| interact | up_right | 6 | 576 × 128 |
| interact | up | 6 | 576 × 128 |
| interact | up_left | 6 | 576 × 128 |
| interact | left | 6 | 576 × 128 |
| interact | down_left | 6 | 576 × 128 |
| attack | down | 6 | 576 × 128 |
| attack | down_right | 6 | 576 × 128 |
| attack | right | 6 | 576 × 128 |
| attack | up_right | 6 | 576 × 128 |
| attack | up | 6 | 576 × 128 |
| attack | up_left | 6 | 576 × 128 |
| attack | left | 6 | 576 × 128 |
| attack | down_left | 6 | 576 × 128 |
| damage | down | 2 | 192 × 128 |
| damage | down_right | 2 | 192 × 128 |
| damage | right | 2 | 192 × 128 |
| damage | up_right | 2 | 192 × 128 |
| damage | up | 2 | 192 × 128 |
| damage | up_left | 2 | 192 × 128 |
| damage | left | 2 | 192 × 128 |
| damage | down_left | 2 | 192 × 128 |
| victory | down | 8 | 768 × 128 |
| victory | down_right | 8 | 768 × 128 |
| victory | right | 8 | 768 × 128 |
| victory | up_right | 8 | 768 × 128 |
| victory | up | 8 | 768 × 128 |
| victory | up_left | 8 | 768 × 128 |
| victory | left | 8 | 768 × 128 |
| victory | down_left | 8 | 768 × 128 |
| defeat | down | 6 | 576 × 128 |
| defeat | down_right | 6 | 576 × 128 |
| defeat | right | 6 | 576 × 128 |
| defeat | up_right | 6 | 576 × 128 |
| defeat | up | 6 | 576 × 128 |
| defeat | up_left | 6 | 576 × 128 |
| defeat | left | 6 | 576 × 128 |
| defeat | down_left | 6 | 576 × 128 |
| cast | down | 7 | 672 × 128 |
| cast | down_right | 7 | 672 × 128 |
| cast | right | 7 | 672 × 128 |
| cast | up_right | 7 | 672 × 128 |
| cast | up | 7 | 672 × 128 |
| cast | up_left | 7 | 672 × 128 |
| cast | left | 7 | 672 × 128 |
| cast | down_left | 7 | 672 × 128 |

## Totals

- 9 states × 8 directions = 72 PNG strips.
- Total authored frames: 576.
- Import target: `assets/enemies/mossling/world_sheet.tres`.
- Importer validates all source files before writing; missing or malformed strips cancel the import without output.

## Current staging observation

The `assets/enemies/mossling/` directory currently contains `source_art/`, `idle_pass_02/`, and `walk_pass_04/`; it does not yet contain the required `animations/` source tree. Existing 4-frame idle and 6-frame walk sheets are partial previews and must not be padded into production art.
