class_name CastleWaterComponent
extends Node2D
## Owns the authored pond zones used by water queries and world interactions.


func is_water_world(world_position: Vector2) -> bool:
	var grid_position := IsoMath.world_to_grid(world_position)
	var zones := get_node_or_null("WaterZones") as Node2D
	if zones == null:
		push_error("CastleWaterComponent requires authored WaterZones.")
		return false
	for marker in zones.get_children():
		if not (marker is Marker2D):
			continue
		var grid_value: Variant = marker.get_meta("grid_position", null)
		var grid_rect: Variant = marker.get_meta("grid_rect") if marker.has_meta("grid_rect") else null
		var radius := float(marker.get_meta("radius")) if marker.has_meta("radius") else 0.0
		if grid_rect is Rect2 and (grid_rect as Rect2).has_point(grid_position):
			return true
		if grid_value is Vector2 and radius > 0.0 and grid_position.distance_to(grid_value) < radius:
			return true
	return false
