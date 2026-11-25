extends SceneTree

func _initialize() -> void:
	call_deferred("_run")


func _find_overlaps(player: CharacterBody2D, shape_node: CollisionShape2D) -> Array[String]:
	var query: PhysicsShapeQueryParameters2D = PhysicsShapeQueryParameters2D.new()
	query.shape = shape_node.shape
	query.transform = shape_node.global_transform
	query.collision_mask = player.collision_mask
	query.exclude = [player.get_rid()]
	var hits: Array[Dictionary] = player.get_world_2d().direct_space_state.intersect_shape(query, 8)
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
	var tested := 0
	var routes := [
		{"name": "WestParterreConnector", "points": [Vector2(560, 790), Vector2(510, 785), Vector2(455, 790), Vector2(420, 810), Vector2(395, 850), Vector2(410, 870)]},
		{"name": "EastParterreConnector", "points": [Vector2(720, 790), Vector2(770, 785), Vector2(825, 790), Vector2(860, 810), Vector2(885, 850), Vector2(870, 870)]}
	]
	for route in routes:
		var road := roads.get_node(str(route["name"])) as Polygon2D
		var points: Array = route["points"]
		for segment in range(points.size() - 1):
			var a: Vector2 = points[segment]
			var b: Vector2 = points[segment + 1]
			var steps := maxi(1, ceili(a.distance_to(b) / 18.0))
			var tangent := (b - a).normalized()
			for step in range(steps + 1):
				var local_point := a.lerp(b, float(step) / float(steps))
				if not Geometry2D.is_point_in_polygon(local_point, road.polygon):
					continue
				var world_point := road.to_global(local_point)
				player.global_position = world_point
				await physics_frame
				for direction in [tangent, -tangent]:
					tested += 1
					if player.test_move(player.global_transform, direction * 16.0):
						blocked.append("%s local=%s world=%s dir=%s overlaps=%s" % [route["name"], local_point, world_point, direction, _find_overlaps(player, shape_node)])
	player.global_position = original
	await physics_frame
	print("CURVED_CONNECTOR_DIRECTIONAL_PROBES=", tested)
	print("CURVED_CONNECTOR_BLOCKED=", blocked.size())
	for issue in blocked:
		print("CURVED_CONNECTOR_BLOCKED_DETAIL ", issue)
	world.queue_free()
	if not blocked.is_empty():
		push_error("CURVED_CONNECTOR_QA_FAILED")
		quit(1)
		return
	print("CURVED_CONNECTOR_COLLISION_OK")
	quit(0)
