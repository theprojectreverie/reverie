extends Node2D
## Four enclosed wading pools. Open floodwater, map perimeter and props stay solid.
## Online expeditions retain their existing server-authoritative traversal.

func _ready() -> void:
	if not MultiplayerGateway.standalone_expedition_id.is_empty():
		return
	for pool_name in ["NorthernMirror", "WestFloodplain", "EasternLake", "SouthernLagoon"]:
		var pool := get_node_or_null(pool_name) as Polygon2D
		var barrier := get_node_or_null(pool_name + "Collision") as StaticBody2D
		if pool == null or barrier == null:
			continue
		pool.add_to_group("wade_water_surface")
		barrier.collision_layer = 0
		# The transparent collision TileMap duplicates the polygon blockers.
		# Also clear boundary-straddling cells: their solid diamonds otherwise
		# produce an invisible wall at a visually accessible shoreline.
		var water_tiles := get_node_or_null("OpenWaterCollision") as TileMapLayer
		if water_tiles != null:
			for cell in water_tiles.get_used_cells():
				var point := water_tiles.to_global(water_tiles.map_to_local(cell))
				if _touches_pool(pool, point):
					water_tiles.erase_cell(cell)
			water_tiles.update_internals()



func _touches_pool(pool: Polygon2D, point: Vector2) -> bool:
	var local := pool.to_local(point)
	if Geometry2D.is_point_in_polygon(local, pool.polygon):
		return true
	# Tile diamonds extend 32 px horizontally and 16 vertically.
	# Keep unrelated collision cells and the open floodwater farther away.
	for offset in [Vector2(-32, 0), Vector2(32, 0), Vector2(0, -16), Vector2(0, 16)]:
		if Geometry2D.is_point_in_polygon(pool.to_local(point + offset), pool.polygon):
			return true
	for i in range(pool.polygon.size()):
		var nearest := Geometry2D.get_closest_point_to_segment(local, pool.polygon[i], pool.polygon[(i + 1) % pool.polygon.size()])
		var d := pool.to_global(nearest) - point
		if absf(d.x) / 32.0 + absf(d.y) / 16.0 <= 1.0:
			return true
	return false
