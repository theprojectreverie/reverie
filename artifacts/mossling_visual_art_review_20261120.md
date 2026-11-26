# Mossling visual art review
Date: 2026-11-20
Scope: inspect existing original concept atlas and staged 6-frame walk preview; no source images modified.

## Established visual identity
- Small woodland / earth minion built from a dense rounded moss canopy and dark root/wood body.
- Bright yellow-green leaf mass, darker olive shadow foliage, warm brown roots/limbs, luminous yellow eyes.
- Distinctive top sprout / curved twig with a single leaf; keep its silhouette recognizable in every direction.
- The eight-direction concept atlas is a static pose reference, not animation source.

## Walk preview observations
- The staged walk sheet is 576 x 1024 RGBA: six horizontal frames per direction, eight direction rows.
- It contains useful authored pose material and is retained as a preview only.
- In the visible sheet, apparent sprite scale and vertical placement vary noticeably between some adjacent cells; isolated-looking root/foot pixels also appear near lower cell edges in several rows. Review frame registration and silhouette continuity before extending this pass.
- Do not auto-center each frame independently: establish one shared pivot / ground-contact baseline per direction and preserve the 96 x 128 canvas.
- Keep canopy and sprout silhouette coherent; motion should come from leg/root alternation, canopy bob, and subtle sprout follow-through, not whole-sprite scale jumps.
- Maintain clear contact shadows/feet within the frame canvas; avoid clipped roots or detached-looking fragments.

## Recommended authored walk cleanup sequence
1. Inspect each of the 48 existing frames at native 1x zoom against its neighbors.
2. Choose a stable ground-contact baseline and character scale for each directional row.
3. Correct only frames with genuine registration or silhouette defects; preserve intended squash/stretch where deliberate.
4. Ensure the six-frame preview forms a readable loop with no accidental duplicate frames.
5. Extend to the full 16 authored frames per direction using distinct in-between poses and consistent timing; do not stretch, repeat, or interpolate the six-frame preview to fake the remaining ten.
6. Re-review all eight directions together at 12 FPS in the existing Godot AnimatedSprite2D preview.

## Measured frame registration audit

A read-only Pillow audit was run against all 48 cells in the staged 576 × 1024 walk preview. All 48 frames contain visible pixels and no two frames within a directional row are exact duplicates. However, the measured alpha bounds confirm the scale/registration concern:

| Direction row | Frame 1 visible height | Typical other-frame visible height |
|---|---:|---:|
| down | 57 px | 94–98 px |
| down-right | 62 px | 92–107 px |
| up-right | 63 px | 107–110 px |
| up | 63 px | 101–107 px |
| left | 64 px | 109–116 px |

Frame 1 is markedly smaller in these five directional rows. The right and down-left rows do not show the same degree of reduction. This is a measurable inconsistency, not merely a visual impression. It should be reviewed as an intentional squash pose versus an accidental scale/pivot discontinuity before extending the cycle.

The complete per-frame alpha bounding boxes are recorded in `artifacts/mossling_walk_frame_audit_20261120.log`. The audit script is `tools/audit_mossling_walk_preview.py`.

## Idle preview registration audit

The four-frame idle sheet (384 × 1024) was also inspected and measured with a read-only alpha-bounds audit. All 32 cells contain visible pixels and no exact duplicates within a directional row. The measurements reveal two items for artist review:

- In several rows, the visible silhouette shifts progressively left across the four frames. For example, down-facing frame bounds move from x=13–96 to x=0–82. This may be intentional sway, but the pivot should be checked in the looping Godot preview so the character does not drift across the world.
- Some left-facing frames reach y=128, the bottom edge of the 128 px canvas. Check whether the lowest pixels are clipped; preserve the ground-contact baseline while correcting any true crop.

The complete measurements are in `artifacts/mossling_idle_frame_audit_20261120.log`; the read-only script is `tools/audit_mossling_idle_preview.py`.

## Production boundary
No production strips are staged yet. These idle and walk previews remain review material, not production art. No source artwork, enemy fallback, or registration state was changed.
