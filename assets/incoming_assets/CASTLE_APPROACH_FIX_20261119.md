# Castle Royal Gardens ceremonial approach fix — 2026-11-19

## Root cause
The authored ApproachPlacements scene had all fifteen flora markers and all six intended decorative prop markers tagged placement_type="disabled". CastleExpansionApproachComponent intentionally skips disabled markers, so the runtime layers were under-populated.

## Fix
- Re-enabled all fifteen authored flora placements and all six intended decorative props (three lantern posts, RoyalStatue, SmallFountain and RoyalBanner).
- Kept BorderPost disabled because it belongs to the separate pathway-border dressing.
- No Castle test expectations were weakened and no procedural placement was added. All assets continue to come from authored scene markers and existing hand-authored PackedScenes.

## Verification
- Live Royal Gardens scene: ExpansionFlora = 15 children.
- Live Royal Gardens scene: ExpansionProps = 8 children (six authored props plus the runtime cache and region portal).
- CASTLE_APPROACH_COUNTS_PASS=true; Godot 4.7.2 process exit code 0.
- Final full-suite verification: **2,627 passed, 0 failed**, Godot 4.7.2 exit code 0. The run emitted the test's intentional corrupt-save recovery warning and one ObjectDB teardown warning.
- The saved screenshot is an earlier visual-review baseline, not a post-fix capture.

No GitHub push has been performed.

