# Zone 2 Pearl City staging
Art direction only, not a locked reference composition. No live scene changes. All coordinates are draft standalone-zone world coordinates; transfer anchors copied from current Zone 2. Open pearl_city_draft.tscn in Godot and place final artist-made props on Marker2D positions after visual review; adjust freely. No generated geometry is used as visual artwork.
- Upper-left gate must span entry road; two independent post collision footprints, clear passage.
- One fountain, park has multiple open approaches. Low flower beds, sparse greenery.
- Market stalls face a broad staggered pedestrian lane; houses on distant right, away from market. Keep existing waystone/spawn and transfer corridors clear.
- Elathra candidate marker only; retain existing patrol and online progression until explicitly integrated. Citizens are waypoint markers, not active NPCs.
- Raw candidate sheets are references only; verify pixel perspective, remove backgrounds, crop and scale consistently, prepare 64x32 diamond terrain, then build individual scenes with foot pivot y-sort and hand-adjusted collisions. Never use whole sheets as map sprites.
- Before promotion: compare live map and draft, test entry/exit, patrol, waystone, player movement, collisions, visual depth and mobile performance.

