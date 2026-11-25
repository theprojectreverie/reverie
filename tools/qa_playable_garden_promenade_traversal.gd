extends SceneTree

func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var packed := load("res://scenes/world/castle_royal_gardens.tscn") as PackedScene
	if packed == null:
		push_error("PROMENADE_TRAVERSAL_WORLD_LOAD_FAILED")
		quit(1)
		return
	var world := packed.instantiate()
	root.add_child(world)
	for frame in range(6):
		await physics_frame
	var player := world.get("player") as CharacterBody2D
	if player == null:
		push_error("PROMENADE_TRAVERSAL_PLAYER_MISSING")
		world.queue_free()
		quit(1)
		return
	var original := player.global_position
	var blocked: Array[String] = []
	var tested := 0
	# Test the authored central promenade in both directions at regular
	# intervals, using the real player collision shape and live physics world.
	for y in range(1210, 480, -32):
		# The central fountain is a deliberate island: the north and south
		# straight approaches terminate at its annular bypass, not through it.
		if y < 1050 and y > 760:
			continue
		player.global_position = Vector2(640.0, float(y))
		await physics_frame
		tested += 1
		if player.test_move(player.global_transform, Vector2.UP * 24.0):
			blocked.append("northward at y=%d" % y)
		player.global_position = Vector2(640.0, float(y - 24))
		await physics_frame
		tested += 1
		if player.test_move(player.global_transform, Vector2.DOWN * 24.0):
			blocked.append("southward at y=%d" % (y - 24))
	player.global_position = original
	await physics_frame
	print("PROMENADE_COLLISION_PROBES=", tested)
	print("PROMENADE_BLOCKED_PROBES=", blocked.size())
	for issue in blocked:
		print("PROMENADE_BLOCKED ", issue)
	world.queue_free()
	if not blocked.is_empty():
		push_error("PROMENADE_TRAVERSAL_HAS_COLLISION_BLOCKS")
		quit(1)
		return
	print("PROMENADE_TRAVERSAL_COLLISION_OK")
	quit(0)
