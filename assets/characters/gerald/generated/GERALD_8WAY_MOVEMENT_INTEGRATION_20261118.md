# Gerald 8-way movement integration — 2026-11-18

Active SpriteFrames resource: assets/characters/gerald/world_sheet.tres

## Idle — 8 directions
- Source: user-uploaded gerald_idle_user_reference_8dir_5f_96x128_upload.png (480x1024)
- Extracted as 40 transparent 96x128 PNG frames under gerald_idle_8dir_5f_96x128/
- Direction rows: DOWN, DOWN_RIGHT, RIGHT, UP_RIGHT, UP, UP_LEFT, LEFT, DOWN_LEFT
- Each idle animation has 5 unique poses, loops at the shared 9 FPS specification.
- The original four-frame front-only idle and transparent/tiny idle directions were replaced.

## Walk — 8 directions
- Source: existing authored walk_sheet.png atlas (1536x1024), 16 columns x 8 direction rows
- Each animation has 16 96x128 AtlasTexture regions and loops at 12 FPS. The original RIGHT and LEFT profile rows contain 12 distinct source drawings among their 16 regions; the other six rows contain 13–16 distinct poses.
- Direction rows: DOWN, DOWN_RIGHT, RIGHT, UP_RIGHT, UP, UP_LEFT, LEFT, DOWN_LEFT.
- This restores the pale-cloak / white-haired Gerald look so the walking art matches the uploaded idle art. The mismatched red/orange 128x128 walk candidates remain archived in generated/ but are no longer active.

## Validation and runtime QA
- verify_gerald_complete_8way_movement.gd: PASS — all 8 idle directions (5 unique poses each), all 8 walk directions (16 atlas regions each), runtime sprite selection.
- verify_gerald_idle_diagonals.gd: PASS — all 8 idles and all 4 diagonal walks.
- verify_gerald_asset_quality.gd: PASS — 72 animations, 576 non-empty frames.
- Production Player runtime: PASS — correct 0.75x Kael height ratio, idle breathing, walk, directional attacks and blade waves.
- Live SpriteFrames visual review captured as GERALD_SPRITEFRAMES_LIVE_VISUAL_QA.png.
- Full project test suite: 2,580 passed, 2 failed. The two failures are unrelated Castle Gardens approach assembly assertions (ExpansionFlora expected 15 children; ExpansionProps expected at least 6); no Gerald movement assertions failed.

## Backups
- world_sheet.tres.pre_diagonal_and_front_idle_20261118.bak
- world_sheet.tres.pre_idle_8dir_5f_20261118.bak
- world_sheet.tres.pre_consistent_8way_walk_20261118.bak
- scripts/art/sprite_frames_actor_source.gd.pre_gerald_diagonals_20261118.bak

No GitHub push has been performed.
