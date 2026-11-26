# Mossling production animation completion checklist
Date: 2026-11-20
Status: ART INCOMPLETE — NO PRODUCTION REGISTRATION

## Authoritative Godot contract
Direction order for every state: 0 down, 1 down-right, 2 right, 3 up-right, 4 up, 5 up-left, 6 left, 7 down-left.

| State | Frames per direction | FPS | Loop |
|---|---:|---:|---|
| idle | 5 | 9 | yes |
| walk | 16 | 12 | yes |
| run | 16 | 16 | yes |
| interact | 6 | 12 | no |
| attack | 6 | 15 | no |
| damage | 2 | 12 | no |
| victory | 8 | 12 | no |
| defeat | 6 | 10 | no |
| cast | 7 | 12 | no |

Each frame canvas: 96 x 128 px. Production requires 9 states x 8 directions = 72 named SpriteFrames animations. Names: <state>_<direction index>.

## Existing staged art — preserve unchanged
- source_art/mossling_8dir_96x128_atlas.png: eight static directional poses; not an animation.
- idle_pass_02/mossling_idle_8dir_4f_96x128.png: 4 frames x 8 directions. Short by one idle frame in every direction; do not duplicate/pad.
- walk_pass_04/mossling_walk_8dir_6f_96x128.png: 6 frames x 8 directions. Preview only; production requires 16 per direction.
- walk_pass_04/mossling_walk_preview.tres and .tscn: eight real Godot AnimatedSprite2D preview animations at 12 FPS; not production registration.

## Art completion matrix
Every cell below requires genuinely distinct authored frames, not duplicated frames, procedural drawing, or interpolation.

| State | Direction strips required | Frame target per strip | Current evidence |
|---|---:|---:|---|
| idle | 8 | 5 | 8 strips x 4; incomplete |
| walk | 8 | 16 | 8 strips x 6; preview only |
| run | 8 | 16 | not staged |
| interact | 8 | 6 | not staged |
| attack | 8 | 6 | not staged |
| damage | 8 | 2 | not staged |
| victory | 8 | 8 | not staged |
| defeat | 8 | 6 | not staged |
| cast | 8 | 7 | not staged |

## Import / release gates
1. Preserve all existing source art and preview resources.
2. Complete all 72 direction/state strips at the exact counts above, maintaining the 96x128 canvas and direction order.
3. Run the existing importer's preflight; it must reject missing/short strips. Never pad with duplicate frames.
4. Generate a real Godot SpriteFrames resource with exact animation names, frame counts, FPS and loop flags.
5. Run SpriteFramesActorSource.validate_sheets(); require zero errors and 72 animations.
6. Run the live roaming-monster scene test and a real battle presentation test. Confirm the authored Sprite2D is visible in-game.
7. Only then register the sheet as production art. Until all gates pass, keep the existing fallback.

## Current release decision
NOT READY. No live enemy renderer or production asset path was changed by this checklist.
