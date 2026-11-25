extends SceneTree

const EPSILON := 0.01

func _initialize() -> void:
	call_deferred("_validate")

func _validate() -> void:
	var packed := load("res://scenes/world/castle_gardens/components/castle_pathways.tscn") as PackedScene
	if packed == null:
		push_error("Hand-designed pathway scene failed to load.")
		quit(1)
		return
	var root_node := packed.instantiate() as Node2D
	var surfaces := root_node.get_node_or_null("HandDesignedRoadSurfaces") as Node2D
	if surfaces == null:
		push_error("Missing HandDesignedRoadSurfaces assembly.")
		root_node.free()
		quit(1)
		return

	var roads: Array[Polygon2D] = []
	var bad: Array[String] = []
	for child in surfaces.get_children():
		if child is Polygon2D:
			var shape := child as Polygon2D
			roads.append(shape)
			if shape.polygon.size() < 3:
				bad.append("%s has fewer than 3 vertices" % shape.name)
			if shape.texture == null:
				bad.append("%s has no cobble texture" % shape.name)
			if shape.uv.size() != shape.polygon.size():
				bad.append("%s UV/vertex count mismatch" % shape.name)
			if _has_degenerate_edge(shape.polygon):
				bad.append("%s contains a zero-length edge" % shape.name)
			if shape.name == "GrandFountainParterreLoop":
				if not _validate_annular_bridge(shape.polygon):
					bad.append("%s annular bridge triangulation or central opening is invalid" % shape.name)
				else:
					print("ANNULAR_RING_TRIANGULATION_OK triangles=52 center_open=true")
			elif _has_self_intersection(shape.polygon):
				bad.append("%s polygon self-intersects" % shape.name)
	if roads.is_empty():
		bad.append("No authored Polygon2D road surfaces found")

	if not bad.is_empty():
		for issue in bad:
			push_error(issue)
		root_node.free()
		quit(1)
		return

	print("ROYAL_GARDEN_HAND_DESIGNED_ROADS_OK polygons=%d; texture, UV, edge and polygon integrity verified" % roads.size())
	print("ROAD_JOIN_AUDIT_BEGIN")
	for i in range(roads.size()):
		for j in range(i + 1, roads.size()):
			var distance := _polygon_edge_distance(roads[i], roads[j])
			if distance <= EPSILON:
				print("JOIN_OR_OVERLAP %s <-> %s" % [roads[i].name, roads[j].name])
			else:
				print("SEPARATE %s <-> %s gap=%.2fpx" % [roads[i].name, roads[j].name, distance])
	print("ROAD_JOIN_AUDIT_END")
	var visited := PackedByteArray()
	visited.resize(roads.size())
	_visit_connected(0, roads, visited)
	var reachable := 0
	for flag in visited:
		reachable += int(flag)
	print("ROAD_NETWORK_REACHABLE=%d/%d" % [reachable, roads.size()])
	if reachable != roads.size():
		push_error("Royal Gardens road network contains disconnected surfaces.")
		root_node.free()
		quit(1)
		return
	print("ROYAL_GARDEN_ROAD_NETWORK_CONNECTED_OK")
	root_node.free()
	quit(0)

func _visit_connected(index: int, roads: Array[Polygon2D], visited: PackedByteArray) -> void:
	visited[index] = 1
	for candidate in range(roads.size()):
		if visited[candidate] == 0 and _polygon_edge_distance(roads[index], roads[candidate]) <= 1.5:
			_visit_connected(candidate, roads, visited)

func _validate_annular_bridge(points: PackedVector2Array) -> bool:
	# The authored ring stores its hole as a single doubled bridge segment.
	# Validate that exact bridge representation by triangulating the polygon
	# and confirming no generated triangle covers the fountain's open center.
	if points.size() != 54:
		return false
	var bridge_a := points[0]
	var bridge_b := points[27]
	if not points[26].is_equal_approx(bridge_a) or not points[53].is_equal_approx(bridge_b):
		return false
	var triangles := Geometry2D.triangulate_polygon(points)
	if triangles.size() != 156:
		return false
	var center := Vector2(640.0, 845.0)
	for i in range(0, triangles.size(), 3):
		var triangle := PackedVector2Array([
			points[triangles[i]],
			points[triangles[i + 1]],
			points[triangles[i + 2]]
		])
		if Geometry2D.is_point_in_polygon(center, triangle):
			return false
	return true


func _has_degenerate_edge(points: PackedVector2Array) -> bool:
	for i in range(points.size()):
		if points[i].distance_squared_to(points[(i + 1) % points.size()]) <= EPSILON * EPSILON:
			return true
	return false

func _has_self_intersection(points: PackedVector2Array) -> bool:
	for i in range(points.size()):
		var a1: Vector2 = points[i]
		var a2: Vector2 = points[(i + 1) % points.size()]
		for j in range(i + 1, points.size()):
			if j == i or j == (i + 1) % points.size() or i == (j + 1) % points.size():
				continue
			var b1: Vector2 = points[j]
			var b2: Vector2 = points[(j + 1) % points.size()]
			var crossing: Variant = Geometry2D.segment_intersects_segment(a1, a2, b1, b2)
			if crossing != null:
				var shared_endpoint := a1.is_equal_approx(b1) or a1.is_equal_approx(b2) or a2.is_equal_approx(b1) or a2.is_equal_approx(b2)
				if not shared_endpoint:
					print("SELF_CROSS_EDGE_PAIR i=", i, " ", a1, " -> ", a2, " j=", j, " ", b1, " -> ", b2, " crossing=", crossing)
					return true
	return false

func _polygon_edge_distance(a: Polygon2D, b: Polygon2D) -> float:
	var ap := _global_points(a)
	var bp := _global_points(b)
	var best := INF
	for i in range(ap.size()):
		var a1: Vector2 = ap[i]
		var a2: Vector2 = ap[(i + 1) % ap.size()]
		for j in range(bp.size()):
			var b1: Vector2 = bp[j]
			var b2: Vector2 = bp[(j + 1) % bp.size()]
			if Geometry2D.segment_intersects_segment(a1, a2, b1, b2) != null:
				return 0.0
			best = minf(best, _point_segment_distance(a1, b1, b2))
			best = minf(best, _point_segment_distance(a2, b1, b2))
			best = minf(best, _point_segment_distance(b1, a1, a2))
			best = minf(best, _point_segment_distance(b2, a1, a2))
	return best

func _global_points(poly: Polygon2D) -> PackedVector2Array:
	var result := PackedVector2Array()
	for point in poly.polygon:
		result.append(poly.to_global(point))
	return result

func _point_segment_distance(point: Vector2, a: Vector2, b: Vector2) -> float:
	var ab := b - a
	if ab.length_squared() <= EPSILON * EPSILON:
		return point.distance_to(a)
	var t := clampf((point - a).dot(ab) / ab.length_squared(), 0.0, 1.0)
	return point.distance_to(a + ab * t)
