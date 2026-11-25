REVERIE — MOSSLING IDLE ART PASS 02
===================================

Source file: mossling_idle_8dir_4f_96x128.png
Canvas: 384 x 1024 px, RGBA.
Layout: 4 columns x 8 direction rows; each frame is 96 x 128 px.
Direction order follows CharacterAnimator:
down, down_right, right, up_right, up, up_left, left, down_left.

QA STATUS: STAGED, NOT PRODUCTION-INTEGRATED.

The sheet provides four idle frames per direction. The authoritative
CharacterAnimationSpecCatalog requires five idle frames per direction.
Therefore this pass is one frame short and MUST NOT be padded with duplicate
frames or registered as a production SpriteFrames source.

The production source contract also requires all 9 states (idle, walk, run,
interact, attack, damage, victory, defeat, cast) across all 8 directions,
with the exact frame counts, FPS and loop flags. The full validation is
enforced by SpriteFramesActorSource.validate_sheets().

Keep this source art intact. Do not replace the current enemy fallback until
a complete, validated SpriteFrames resource exists and a real battle test
confirms the art is being displayed.
