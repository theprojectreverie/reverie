extends Minimap
# Original per-cell collection kept only as a verification oracle.
func _collect_map_art(node: Node, inherited_z: int, tint: Color) -> void:
	if node is CanvasLayer or node is Control or node is Camera2D or node is CharacterBody2D or node is Interactable:
		return
	var lower := str(node.name).to_lower()
	if "fog" in lower or "background" in lower or "camera" in lower or "revienna" in lower or "light" in lower or "transferpoints" in lower or "fairy" in lower:
		return
	var z := inherited_z
	var color := tint
	if node is CanvasItem:
		if not node.is_visible_in_tree():
			return
		z = inherited_z + node.z_index if node.z_as_relative else node.z_index
		color *= node.modulate
	if node is Sprite2D:
		var sprite := node as Sprite2D
		if sprite.texture != null:
			var local_rect := sprite.get_rect()
			var source := sprite.region_rect if sprite.region_enabled else Rect2(Vector2.ZERO, sprite.texture.get_size())
			_add_map_art(sprite.texture, local_rect, source, sprite.global_transform, z, color * sprite.self_modulate, sprite.flip_h, sprite.flip_v)
	if node is TileMapLayer:
		var layer := node as TileMapLayer
		if layer.tile_set != null:
			for cell in layer.get_used_cells():
				var source_id := layer.get_cell_source_id(cell)
				if not layer.tile_set.has_source(source_id):
					continue
				var atlas := layer.tile_set.get_source(source_id) as TileSetAtlasSource
				if atlas == null or atlas.texture == null:
					continue
				var coords := layer.get_cell_atlas_coords(cell)
				if not atlas.has_tile(coords):
					continue
				var region := Rect2(atlas.get_tile_texture_region(coords))
				var tile_data := layer.get_cell_tile_data(cell)
				var offset := Vector2(tile_data.texture_origin) if tile_data != null else Vector2.ZERO
				var local_rect := Rect2(layer.map_to_local(cell) - region.size * 0.5 + offset, region.size)
				_add_map_art(atlas.texture, local_rect, region, layer.global_transform, z + (tile_data.z_index if tile_data != null else 0), color * layer.self_modulate, tile_data.flip_h if tile_data != null else false, tile_data.flip_v if tile_data != null else false)
	for child in node.get_children():
		_collect_map_art(child, z, color)
