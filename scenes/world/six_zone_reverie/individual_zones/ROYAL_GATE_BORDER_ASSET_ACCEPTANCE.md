# Royal Gate — Native Stone Border and Corner Acceptance Specification
Updated: 2026-11-22
Scope: Zone 02 only; no changes to any other zones or collisions.

## Reference image and pixel geometry
- Authoritative source: res://assets/environment/royal_gardens_ground_64x32/garden_stone_path.png
- Native paving footprint: 64 × 32 pixels, 2:1 diamond isometric perspective.
- Native stone has a fully opaque 1008-pixel diamond and 1040 transparent pixels, with no partially transparent pixels. This gives crisp, pixel-art tile edges.
- Dominant midtone median among the medium/light stone surface: RGB (226,188,174), approximately #E2BCAE; mean RGB (219,183,169).
- The stone texture has warm blush/peach paving and dark, high-contrast diamond-shaped grout. Lavender/purple-gray paving with bright gold/green trims is not an acceptable direct replacement.
- Placeable road tile origins in Zone 02 share x modulo 32 = 18 and y modulo 16 = 12 in standalone/world coordinates. Native tile origin is the upper-left of its 64×32 PNG, not its center.
- Border/corner sprites must include the exact final 64×32 artwork or be explicit 64×32 decorative overlays with transparent pixels, not 64×40 sprites assumed to fit by scaling.

## Asset set design brief
- Straight paving-to-grass transitions on both diagonal orientations.
- Four convex outside corners, four concave inside corners, a T-junction corner finish, and short taper/end caps.
- No isolated flowers, walls, lanterns, or protruding gold ornaments merged into repeatable terrain sprites. Those remain separate Sprite2D decorations.
- Keep geometry aligned with the original diamond paving silhouette, consistent shadows and stone texture. Where the border ends, the stone edge must meet the neighbor's exact 64×32 diamond.
- Transparent background throughout, including between stone/grass/curb details. Do not include flat purple, white, or checkerboard mattes.

## Approval requirements
1. Inspect alpha on every final RGBA PNG on both dark and bright backgrounds; reject residual background colors, fringe halos, or clipped edge pixels.
2. Test neighboring placements at their actual diamond-grid positions (not a contact sheet of isolated samples). No visible 1px gaps, step discontinuities, double grout lines, or raised-looking curb blocks.
3. Compare against authentic native stone source, not unrelated castle tiles.
4. Verify 64×32 footprint, consistency at both normal game zoom and zoomed pixel-level view, and accurate scene import.
5. Use only editor-authored Godot node/TileMap scenes for visible map presentation; no script-generated or placeholder artwork.
6. Do not add collision or modify existing zone transfers.
7. No download pack or final-approval claim until all criteria pass.

## Editor test scene
- royal_gate_border_fit_review.tscn: native tile patch alongside the rejected lavender border candidate on the same native-tile base. This is a QA scene only, not imported in Royal Gate.
- Do not deploy border_ne.png from the rejected pack to the playable Zone 02 scene.

## Current acceptance status
- Existing lavender/gold border candidate is NOT approved: wrong color and dimensions (64×40 vs 64×32) and does not join native stone seamlessly.
- Native existing 64×32 pave geometry is technically connected and valid.
- Matching *hand-designed* border/corner assets remain to be developed and artistically approved.
