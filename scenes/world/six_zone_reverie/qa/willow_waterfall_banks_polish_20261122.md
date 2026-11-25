# Willow Fields — waterfall and banks polish (2026-11-22)

## Saved to playable zone
- Extended the first two vertices of the native, editable WillowRiverContinuousArt Polygon2D farther underneath the waterfall's hand-painted splash pool. The river texture, remaining 23 vertices and 32x32 source artwork remain unchanged.
- Removed two incompatible blue-square-backed riverbank-rock Sprite2D props (RiverbankRocksSouthEast and RiverbankRocksMid); the original PNG remains stored in assets, but is no longer loaded by this scene.
- Relocated WaterLilyBloomEast from (1450, 2000) to (1350, 2010) so it sits inside the river rather than touching the meadow bank.
- No changes to the 10000 ground cells, 1395 path cells, Kael scale/camera, entrance/exits, or collision systems.

## Live QA
- Waterfall close-up: Downloads/willow_waterfall_mouth_wide.jpg (compared against softer option).
- Clean south river bank and centered lily: Downloads/willow_south_riverbank_current.jpg.
- Bridge-side reference: Downloads/willow_bridge_riverbank_current.jpg.
- Headless Godot standalone launch successful; resource, geometry and node integrity checks passed.

## Remaining
- Central dirt junction is still oversized and visually blocky.
- The waterfall's bright blue pool is not yet color matched to the deeper teal river; a purpose-designed bank/foam art transition would improve this without changing existing hand-painted assets.
- Final in-game traversal and mobile-performance tests pending.
