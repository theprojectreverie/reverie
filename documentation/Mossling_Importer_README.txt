REVERIE — MOSSLING AUTHORED ART IMPORTER

Purpose
-------
This EditorScript imports finished artist-authored Mossling animation strips into
a native Godot SpriteFrames resource. It does not generate or draw artwork.

Required source layout
----------------------
assets/enemies/mossling/animations/
  idle/down.png ... idle/down_left.png
  walk/down.png ... walk/down_left.png
  run/down.png ... run/down_left.png
  interact/down.png ... interact/down_left.png
  attack/down.png ... attack/down_left.png
  damage/down.png ... damage/down_left.png
  victory/down.png ... victory/down_left.png
  defeat/down.png ... defeat/down_left.png
  cast/down.png ... cast/down_left.png

Each PNG is one horizontal strip with transparent background. Frame size is
96x128. Strip width must equal the state's exact frame count multiplied by 96.

Frame contract (per direction)
------------------------------
idle       5 @ 9 fps   loop
walk      16 @ 12 fps  loop
run       16 @ 16 fps  loop
interact   6 @ 12 fps  once
attack     6 @ 15 fps  once
damage     2 @ 12 fps  once
victory    8 @ 12 fps  once
defeat     6 @ 10 fps  once
cast       7 @ 12 fps  once

Total: 9 states x 8 directions = 72 animations, 576 frames.

Run
---
Open tools/import_mossling_spriteframes.gd in the Godot editor and use
File > Run (or the EditorScript run shortcut). The script performs a complete
preflight first. If any strip is missing, has the wrong dimensions, or lacks
transparent top-left background, it cancels without writing the output.

Output
------
assets/enemies/mossling/mossling_sprite_frames.tres

The source PNGs are never modified. Do not register the result in live combat
until the full set has been artist-authored and a real battle scene verifies it.
