extends SceneTree

func _initialize() -> void:
	call_deferred("_run")


func _cross(a: Vector2, b: Vector2) -> float:
	return a.x * b.y - a.y * b.x


func _ray_band_center(polygon: PackedVector2Array, origin: Vector2, direction: Vector2) -> Variant:
	var ray_end := origin + direction * 900.0
	var distances: Array[float] = []
	for i in range(polygon.size()):
		var a := polygon[i]
		var b := polygon[(i + 1) % polygon.size()]
		var edge := b - a
		var denom := _cross(direction, edge)
		if absf(denom) < 0.0001:
			continue
		var offset := a - origin
		var t := _cross(offset, edge) / denom
		var u := _cross(offset, direction) / denom
		if t >= 0.0 and t <= 900.0 and u >= 0.0 and u <= 1.0:
			distances.append(t)
	distances.sort()
	var best_width := 0.0
	var best_center: Variant = null
	for i in range(distances.size() - 1):
		var near_t: float = distances[i]
		var far_t: float = distances[i + 1]
		var width := far_t - near_t
		if width < 18.0 or width > 180.0:
			continue
		var midpoint := origin + direction * ((near_t + far_t) * 0.5)
		if Geometry2D.is_point_in_polygon(midpoint, polygon) and width > best_width:
			best_width = width
			best_center = midpoint
	return best_center


func _find_overlaps(player: CharacterBody2D, shape_node: CollisionShape2D) -> Array[String]:
	var query := PhysicsShapeQueryParameters2D.new()
	query.shape = shape_node.shape
	query.transform = shape_node.global_transform
	query.collision_mask = player.collision_mask
	query.exclude = [player.get_rid()]
	var hits := player.get_world_2d().direct_space_state.intersect_shape(query, 8)
	var names: Array[String] = []
	for hit in hits:
		var collider := hit.get("collider") as Node
		names.append("%s @ %s" % [collider.get_path(), collider.global_position] if collider != null else "unknown")
	return names


func _run() -> void:
	var packed := load("res://scenes/world/castle_royal_gardens.tscn") as PackedScene
	var world := packed.instantiate()
	root.add_child(world)
	for frame in range(6):
		await physics_frame
	var player := world.get("player") as CharacterBody2D
	var roads := world.get_node("PathwayTiles/HandDesignedRoadSurfaces") as Node2D
	var shape_node := player.get_node("CollisionShape2D") as CollisionShape2D
	var original := player.global_position
	var blocked: Array[String] = []
	var outside := 0
	var invalid_details: Array[String] = []
	var tested := 0
	var routes := [
		{"name": "WestFountainGardenLoop", "center": Vector2(390, 690)},
		{"name": "EastFountainGardenLoop", "center": Vector2(900, 690)},
		{"name": "GrandFountainParterreLoop", "center": Vector2(640, 845)}
	]
	for route in routes:
		var road := roads.get_node(str(route["name"])) as Polygon2D
		var center: Vector2 = route["center"]
		var samples: Array[Vector2] = []
		for sample in range(72):
			var angle := TAU * float(sample) / 72.0
			var point: Variant = _ray_band_center(road.polygon, center, Vector2(cos(angle), sin(angle)))
			if point == null:
				samples.append(Vector2(INF, INF))
			else:
				samples.append(point)
		# A single ray can graze a near-parallel authored edge. Recover it
		# from the nearest valid samples on both sides; retain an explicit
		# failure only if no recovered point lies inside the road polygon.
		for i in range(samples.size()):
			if samples[i].is_finite():
				continue
			var previous := Vector2(INF, INF)
			var following := Vector2(INF, INF)
			for distance in range(1, samples.size()):
				var before: Vector2 = samples[(i - distance + samples.size()) % samples.size()]
				var after: Vector2 = samples[(i + distance) % samples.size()]
				if not previous.is_finite() and before.is_finite():
					previous = before
				if not following.is_finite() and after.is_finite():
					following = after
				if previous.is_finite() and following.is_finite():
					break
			var recovered := previous if previous.is_finite() and Geometry2D.is_point_in_polygon(previous, road.polygon) else following
			if recovered.is_finite() and Geometry2D.is_point_in_polygon(recovered, road.polygon):
				samples[i] = recovered
			else:
				invalid_details.append("%s angle=%d" % [route["name"], i])
		for sample in range(samples.size()):
			var local_point: Vector2 = samples[sample]
			var next_point: Vector2 = samples[(sample + 1) % samples.size()]
			if not local_point.is_finite() or not next_point.is_finite():
				outside += 1
				continue
			if not Geometry2D.is_point_in_polygon(local_point, road.polygon):
				outside += 1
				continue
			var tangent := (next_point - local_point).normalized()
			if tangent.length_squared() < 0.5:
				continue
			player.global_position = road.to_global(local_point)
			await physics_frame
			for direction in [tangent, -tangent]:
				tested += 1
				if player.test_move(player.global_transform, direction * 14.0):
					blocked.append("%s sample=%d local=%s dir=%s overlaps=%s" % [route["name"], sample, local_point, direction, _find_overlaps(player, shape_node)])
	player.global_position = original
	await physics_frame
	print("FOUNTAIN_PERIMETER_DIRECTIONAL_PROBES=", tested)
	print("FOUNTAIN_PERIMETER_BLOCKED=", blocked.size())
	print("FOUNTAIN_PERIMETER_INVALID_CENTERLINE_SAMPLES=", outside)
	for detail in invalid_details:
		print("FOUNTAIN_PERIMETER_INVALID_DETAIL ", detail)
	for issue in blocked:
		print("FOUNTAIN_PERIMETER_BLOCKED_DETAIL ", issue)
	world.queue_free()
	if not blocked.is_empty() or outside > 0:
		push_error("FOUNTAIN_PERIMETER_QA_FAILED")
		quit(1)
		return
	print("FOUNTAIN_PERIMETER_COLLISION_OK")
	quit(0)
