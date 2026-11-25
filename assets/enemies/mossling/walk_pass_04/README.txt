REVERIE — MOSSLING WALK PREVIEW, PASS 04
========================================

Files:
- mossling_walk_8dir_6f_96x128.png
  6 columns x 8 direction rows. Each frame is 96x128 RGBA.
- mossling_walk_preview.tres
  Godot 4 SpriteFrames with eight real looping AnimatedSprite2D animations:
  walk_0 through walk_7, each at 12 FPS.
- mossling_walk_preview.tscn
  A minimal preview scene that plays walk_0.

Direction order:
0 down, 1 down_right, 2 right, 3 up_right,
4 up, 5 up_left, 6 left, 7 down_left.

IMPORTANT:
This is a six-frame walk preview only. The Reverie production animation
catalog currently specifies 16 frames for WALK and requires nine states
across all eight directions. Do not register this preview as a complete
production enemy sheet or replace the live enemy renderer with it.
Use it to review the authored style, direction consistency, and motion.
