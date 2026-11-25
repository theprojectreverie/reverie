extends SceneTree

func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var packed := load("res://scenes/world/castle_royal_gardens.tscn") as PackedScene
	var world := packed.instantiate()
	root.add_child(world)
	for frame in range(6):
		await physics_frame
	var player := world.get("player") as CharacterBody2D
	var roads := world.get_node_or_null("PathwayTiles/HandDesignedRoadSurfaces") as Node2D
	if player == null or roads == null:
		push_error("GATE_APPROACH_WORLD_SETUP_FAILED")
		world.queue_free()
		quit(1)
		return
	var original := player.global_position
	var blocked: Array[String] = []
	var probes := 0
	# Both lower gate walks have long straight runs. Their world-space
	# centerlines are derived from the authored scene transform:
	# world_x = -648.32 + 2.013 * local_x.
	var corridors := [
		{"name": "WestLowerGateWalk", "x": 26.0},
		{"name": "EastLowerGateWalk", "x": 1260.0}
	]
	for corridor in corridors:
		var x := float(corridor["x"])
		for y in range(1070, 1291, 20):
			player.global_position = Vector2(x, float(y))
			await physics_frame
			probes += 1
			if player.test_move(player.global_transform, Vector2.UP * 16.0):
				blocked.append("%s north y=%d" % [corridor["name"], y])
			probes += 1
			if player.test_move(player.global_transform, Vector2.DOWN * 16.0):
				blocked.append("%s south y=%d" % [corridor["name"], y])
	player.global_position = original
	await physics_frame
	print("GATE_APPROACH_COLLISION_PROBES=", probes)
	print("GATE_APPROACH_BLOCKED=", blocked.size())
	for issue in blocked:
		print("GATE_APPROACH_BLOCKED_DETAIL ", issue)
	world.queue_free()
	if not blocked.is_empty():
		push_error("GATE_APPROACH_COLLISION_BLOCKS_FOUND")
		quit(1)
		return
	print("GATE_APPROACH_COLLISION_OK")
	quit(0)
