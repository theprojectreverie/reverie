# Reverie — Mossling production animation brief

Status: ART SPECIFICATION / NOT A LIVE RESOURCE
Target: `res://assets/enemies/mossling/`

## Identity and visual direction

- ID/name: `mossling` / Mossling
- Encounter role: common Earth minion
- Lore: “A clump of moss that grew a grudge. Harmless alone; the glade is never alone.”
- Palette anchors from `resources/data/enemies.json`:
  - Primary bark/earth: `#4f6b3a`
  - Secondary moss: `#8fbf6a`
  - Accent/eyes: `#d9ff9f`
- Preserve the approved concept's compact moss-covered stump silhouette, layered foliage, twig growth and readable glowing eyes.
- Art target is the game's crisp pixel-art language. Use deliberate pixel clusters and a restrained palette; do not use smooth vector shapes, painted gradients, blur, or code-drawn body parts.
- Keep the complete creature within a 96×128 transparent frame. Ground contact and visual center must remain stable between frames.

## Direction contract

Each state must contain these eight directional animations in exactly this order:

0. down
1. down_right
2. right
3. up_right
4. up
5. up_left
6. left
7. down_left

Do not mirror left/right frames. The game addresses all eight directions independently.

## Required animation matrix

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

Total: 72 frames per direction × 8 directions = 576 individual 96×128 frames.

Animation names must be `<state>_<direction_index>`, e.g. `idle_0`, `walk_2`, `attack_6`, `cast_7`.

## Motion direction

- Idle: gentle body settle, tiny moss/leaf movement, readable loop seam.
- Walk: clear alternating stump-foot contacts; body mass moves with the feet, foliage lags subtly.
- Run: faster, stronger forward lean and compressed contact/recovery; visibly distinct from walk.
- Interact: a short curious lean/reach with a twig or leaf gesture; return is handled by the animator.
- Attack: telegraph → compact moss/root slam → recovery. Keep the impact readable inside the frame.
- Damage: two distinct recoil frames; do not drift the ground anchor.
- Victory: relieved/proud bounce and a small leaf flourish; finish on a stable pose.
- Defeat: loss of lift, foliage droop and collapse; last frame remains readable.
- Cast: gather soft green light around the eyes/foliage, release it, then settle. Keep this visually distinct from the physical slam.

## Existing art-pass disposition

- `source_art/mossling_8dir_96x128_atlas.png`: eight-direction static concept poses only.
- `idle_pass_02/mossling_idle_8dir_4f_96x128.png`: four idle frames per direction. This does not meet the five-frame idle contract.
- Neither file is a complete production animation source. Preserve both as source/reference art. Do not duplicate a frame to pad the idle loop and do not replace the live enemy renderer with a partial sheet.

## Godot registration gate

Only register the final sliced `SpriteFrames` resource after:
1. All 9 states × 8 directions exist (72 animations).
2. Every animation has the exact frame count, FPS and loop flag above.
3. Every frame is a non-null 96×128 texture with transparency.
4. The 8 directions remain independently authored and correctly ordered.
5. `SpriteFramesActorSource.validate_sheets()` returns an empty error array.
6. A real Mossling battle confirms the sheet is visible and idle/attack/damage/defeat transitions play correctly.

Keep the current enemy fallback until all six gates pass. Do not change combat data, turn timing, targeting, hitboxes, or gameplay rules as part of this art task.
