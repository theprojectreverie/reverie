# Reverie - Act I map artwork

- act1_overworld_panorama.png is the main 2:1 pixel-art environment panorama (128x64, 24-color Pixel Engine output).
- act1_overworld_panorama.pxpen is the editable PixelPen project source, imported and palette-quantized through PixelPen's own project format.
- The six region-specific images remain as individual bottom-strip thumbnails.
- scenes/ui/components/act1_map_atlas.tscn owns the visual layout.
- The panorama, six region labels, current-region marker, quest marker, and thumbnail strip are scene nodes.
- The road is painted into the panorama art. There is no generated Line2D road, procedural terrain, noise map, polygon map background, or _draw map renderer.
- scripts/ui/act1_map_atlas.gd only updates node positions and live state labels/markers.
