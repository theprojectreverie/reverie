extends SceneTree

func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	# Test the authored arrival marker, not a position from the persistent save.
	# This reset is in-memory only and does not alter the user's save file.
	var state := root.get_node_or_null("GameState")
	if state != null:
		var session = state.get("session_domain")
		if session != null:
			session.player_region = "greenward"
			session.active_world_id = "greenward"
			session.has_player_position = false
			session.region_positions.erase("castle_royal_gardens")
	var packed := load("res://scenes/world/castle_royal_gardens.tscn") as PackedScene
	if packed == null:
		push_error("PLAYABLE_GARDEN_LOAD_FAILED")
		quit(1)
		return
	var world := packed.instantiate() as Node2D
	root.add_child(world)
	for frame in range(5):
		await process_frame
	var pathway_root := world.get_node_or_null("PathwayTiles") as Node2D
	var roads := world.get_node_or_null("PathwayTiles/HandDesignedRoadSurfaces") as Node2D
	if pathway_root == null or roads == null:
		push_error("PLAYABLE_GARDEN_HAND_DESIGNED_ROADS_MISSING")
		world.queue_free()
		quit(1)
		return
	var polygon_count := 0
	var invalid_polygons: Array[String] = []
	for child in roads.get_children():
		if child is Polygon2D:
			polygon_count += 1
			var road := child as Polygon2D
			if road.polygon.size() < 3 or road.texture == null or road.uv.size() != road.polygon.size():
				invalid_polygons.append(str(road.name))
	if polygon_count != 10 or not invalid_polygons.is_empty():
		push_error("PLAYABLE_ROAD_ASSEMBLY_INVALID polygons=%d invalid=%s" % [polygon_count, str(invalid_polygons)])
		world.queue_free()
		quit(1)
		return
	var player := world.get("player") as Node2D
	if player == null or not is_instance_valid(player):
		push_error("PLAYABLE_GARDEN_PLAYER_NOT_SPAWNED")
		world.queue_free()
		quit(1)
		return
	var spawn_on_road := false
	for child in roads.get_children():
		if child is Polygon2D:
			var road := child as Polygon2D
			var global_polygon := PackedVector2Array()
			for vertex in road.polygon:
				global_polygon.append(road.to_global(vertex))
			if Geometry2D.is_point_in_polygon(player.global_position, global_polygon):
				spawn_on_road = true
				break
	var open_directions := 0
	for direction in [Vector2.RIGHT, Vector2.LEFT, Vector2.UP, Vector2.DOWN]:
		if not player.test_move(player.global_transform, direction * 28.0):
			open_directions += 1
	if not spawn_on_road or open_directions < 2:
		push_error("PLAYABLE_SPAWN_NOT_CLEAR spawn_on_road=%s open_directions=%d" % [str(spawn_on_road), open_directions])
		world.queue_free()
		quit(1)
		return
	print("PLAYABLE_GARDEN_LOAD_OK")
	print("PLAYABLE_HAND_DESIGNED_ROAD_POLYGONS=", polygon_count)
	print("PLAYABLE_ROAD_ROOT_POSITION=", roads.global_position, " SCALE=", roads.global_scale)
	print("PLAYABLE_PLAYER_SPAWN=", player.global_position, " ON_ROAD=", spawn_on_road)
	print("PLAYABLE_SPAWN_CLEAR_DIRECTIONS=", open_directions, "/4")
	print("PLAYABLE_GARDEN_ROAD_SCENE_SMOKE_OK")
	world.queue_free()
	quit(0)
