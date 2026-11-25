# Willow Fields — asset transparency and duplicate QA (2026-11-23)

## Actual asset inspection
- Checked all four `artist_road_transitions_v3/handdrawn_direction_*.png` files and all eight `artist_road_transitions_v4/straight_edge_*.png` files.
- Every file is 64x32 pixels, with 993 fully transparent pixels, 1055 fully opaque pixels and no partially transparent pixels. The transparency is genuine; this check does not establish good-looking grass/dirt transitions.
- SHA-256 file hashes reveal that `straight_edge_1_0.png` and `straight_edge_1_1.png` are exact duplicates. Other files in the tested set have different file hashes.

## Production decision
- Do not blindly replace one duplicate with a rotated or mirrored image: orientation and grass/dirt seams must be visually approved first.
- No production asset or scene was modified by this audit.
- Next step: hand-design the missing directional variant and inner/outer corner transitions, then compare against native ground at 1x and deploy only accepted scenes.

## Existing constraints
- Six-zone Willow only; editor-authored nodes and hand-designed art; no collision additions; keep Kael and exploration camera scales unchanged.
