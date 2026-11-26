extends RefCounted
## Shared authored geometry, used only by the two opening story regions.
const PATH := "res://resources/data/story_opening_regions.json"

static func load_region(region_id: String) -> Dictionary:
	var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(PATH))
	if not data is Dictionary:
		return {}
	var region: Variant = data.get(region_id, {})
	return region if region is Dictionary else {}

static func spawn(region: Dictionary) -> Vector2:
	var coords: Array = region.get("spawn", [0, 0])
	return Vector2(float(coords[0]), float(coords[1]))

static func contains(region: Dictionary, point: Vector2) -> bool:
	if region.is_empty() or not point.is_finite():
		return false
	var outline := PackedVector2Array()
	for pair in region.get("outline", []):
		outline.append(Vector2(float(pair[0]), float(pair[1])))
	return outline.size() >= 3 and Geometry2D.is_point_in_polygon(point, outline)
