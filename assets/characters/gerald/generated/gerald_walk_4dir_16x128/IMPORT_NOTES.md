# Gerald Funny Walk — Import Notes

- Source: 64 hand-authored transparent PNG frames, 128x128 each.
- Frame groups: front_01..16, right_01..16, back_01..16, left_01..16.
- Runtime mapping: walk_0 = front/down; walk_2 = right; walk_4 = back/up; walk_6 = left.
- Playback: 16 frames per cardinal direction, looping at 12 FPS.
- All 64 source frames were checked for distinct pixel content.
- Existing diagonal walk animations (walk_1, walk_3, walk_5, walk_7) remain intact.
- Existing idle, run, interact, attack, cast, damage, victory and defeat animations remain intact.
- Gerald's cardinal walk frames are intentionally kept at the requested 128x128 canvas; SpriteFramesActorSource validation allows this one scoped exception. Other world frames retain the 96x128 standard.
- Resource: res://assets/characters/gerald/world_sheet.tres
- Pre-change backup: world_sheet.tres.pre_funny_walk_20261118.bak
