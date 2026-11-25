# Willow Fields — targeted road-edge replacement plan (2026-11-23)

## Production references verified
- `wf_narrow_straight_edge_1_0` occurs as an instance in the production Willow scene **39** times.
- `wf_narrow_straight_edge_1_1` occurs **40** times.
- Their respective source PNGs are byte-identical despite different names, meaning **79 placed scene instances** currently share the same art.

## Safe art replacement protocol
1. Create a distinctly illustrated 64x32 pixel-art directional `straight_edge_1_1.png` variant with true transparent corners and no white background. Do not merely mirror or rotate without visual confirmation of its orientation.
2. Preview both variants over the existing grass/dirt base, including the junction and bridge approach, at 1x gameplay scale.
3. Keep the existing editor-authored packed scenes and replace only the approved source texture so all 40 `1_1` instances update consistently.
4. Run the standalone scene and visually inspect 1_0 vs 1_1 plus inner/outer corners. Roll back if any new seams appear.

## Current state
No production textures or scene instances were changed by this audit. No collision, camera or character-scale changes. Remaining road seams and waterfall color mismatch are not resolved.
