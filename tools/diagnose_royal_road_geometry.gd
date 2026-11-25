extends SceneTree

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var packed := load("res://scenes/world/castle_gardens/components/castle_pathways.tscn") as PackedScene
	if packed == null:
		quit(2)
		return
	var root := packed.instantiate()
	var surface := root.get_node("HandDesignedRoadSurfaces")
	var roads: Array[Polygon2D] = []
	for child in surface.get_children():
		if child is Polygon2D:
			roads.append(child)
	print("ROAD_GEOMETRY_DIAGNOSTIC polygons=", roads.size())
	for i in range(roads.size()):
		for j in range(i + 1, roads.size()):
			var a := _global_points(roads[i])
			var b := _global_points(roads[j])
			var best := INF
			var best_a := Vector2.ZERO
			var best_b := Vector2.ZERO
			for ai in range(a.size()):
				var a1: Vector2 = a[ai]
				var a2: Vector2 = a[(ai + 1) % a.size()]
				for bi in range(b.size()):
					var b1: Vector2 = b[bi]
					var b2: Vector2 = b[(bi + 1) % b.size()]
					var pair := _segment_closest(a1, a2, b1, b2)
					if pair[0] < best:
						best = pair[0]
						best_a = pair[1]
						best_b = pair[2]
			if best < 0.5:
				print("TOUCH/OVERLAP ", roads[i].name, " <-> ", roads[j].name, " distance=", snappedf(best, 0.01))
			else:
				print("GAP ", roads[i].name, " <-> ", roads[j].name, " distance=", snappedf(best, 0.01), " at ", best_a, " / ", best_b)
	root.free()
	quit(0)

func _global_points(poly: Polygon2D) -> PackedVector2Array:
	var result := PackedVector2Array()
	for point in poly.polygon:
		result.append(poly.to_global(point))
	return result

func _segment_closest(a: Vector2, b: Vector2, c: Vector2, d: Vector2) -> Array:
	var best := INF
	var pa := Vector2.ZERO
	var pb := Vector2.ZERO
	for p in [a, b]:
		var q := _closest_on_segment(p, c, d)
		if p.distance_to(q) < best:
			best = p.distance_to(q)
			pa = p
			pb = q
	for p in [c, d]:
		var q := _closest_on_segment(p, a, b)
		if p.distance_to(q) < best:
			best = p.distance_to(q)
			pa = q
			pb = p
	if Geometry2D.segment_intersects_segment(a, b, c, d) != null:
		return [0.0, (a+b)*0.5, (c+d)*0.5]
	return [best, pa, pb]

func _closest_on_segment(p: Vector2, a: Vector2, b: Vector2) -> Vector2:
	var ab := b-a
	if ab.length_squared() <= 0.000001:
		return a
	return a + ab * clampf((p-a).dot(ab) / ab.length_squared(), 0.0, 1.0)
