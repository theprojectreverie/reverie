# Reverie — Act I: The Royal Road
## Canonical world-layout and art-direction reference

Status: design reference, not a runtime scene or a flattened map background.
Source: user-provided reference image, 2026-11-18.

## Landmark order

1. **Royal Gardens** — opening region; ornate rose-pink and antique-gold royal estate, formal pools, blossom trees, paved promenades and the castle.
2. **Royal Gate** — threshold out of the estate; monumental gatehouse and a clear road transition from manicured garden to open countryside.
3. **Willow Fields** — warm golden meadow region with windmill, cottages, hedgerows and gentle rolling terrain.
4. **Elderwood Grove** — dense, cool woodland with purple wisteria, deep green canopy, streams, stepping stones and waterfalls.
5. **Forsaken Ruins** — broken stonework, crimson trees, dark ground and fractured road edges; atmosphere shifts toward danger.
6. **Ruined Tower** — final landmark; tall violet-lit tower, fractured masonry, purple crystals, waterfalls and a strong moonlit silhouette.

## World composition

- The road is the visual and navigational spine. It should wind continuously between all six landmarks, with readable bends and gentle elevation changes.
- The route should feel like a journey across a broad world, not six adjacent decorative panels. Preserve meaningful travel distance and distinct transition spaces between landmarks.
- Keep each landmark visually identifiable from its own silhouette and palette. Do not allow one biome's dominant props to spill indiscriminately into the next.
- Use foreground, middle-ground and distant layers to create depth. The road must remain legible above decorative ground detail.
- Landmark labels and route markers belong to the world-map / journey presentation layer, not baked into terrain textures.
- The lower reference strip is a visual progression summary, not a second playable map.

## Palette and atmosphere progression

| Region | Dominant visual language |
|---|---|
| Royal Gardens | rose pink, lavender, warm ivory stone, antique gold, lush green |
| Royal Gate | royal gold, rose accents, dark iron, pale stone |
| Willow Fields | wheat gold, soft green, warm timber, cottage amber |
| Elderwood Grove | deep emerald, teal water, violet and magenta foliage, cool blue falls |
| Forsaken Ruins | charcoal stone, muted crimson foliage, dusty mauve, broken masonry |
| Ruined Tower | deep violet, moonlit purple, luminous crystals, cold waterfall blue |

## Production rules

- Build every region from individually editable Godot scenes and authored node hierarchies.
- Reuse modular terrain and road pieces only where their shapes genuinely fit. Curves, junctions, banks and transitions must be intentionally composed.
- Keep large landmark architecture, trees, waterfalls, bridges and fountains as natural-size multi-cell props.
- Keep collision and navigation geometry separate from decorative sprite bounds; validate the actual player collider along the whole intended route.
- No procedural scenery, code-generated art, generic placeholders, or single flattened reference-image background.
- Preserve the existing playable Royal Gardens while the remaining regions are developed as separate scenes and connected through the world-navigation / journey flow.
- The reference image establishes composition and mood, not exact pixel dimensions or a final in-game camera scale.

## Current implementation boundary

The playable Royal Gardens scene is the current production starting point. The other five landmarks are target regions in the reference sequence; this document does not claim they are already implemented or connected.
