extends SceneTree

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var packed := load("res://scenes/world/castle_royal_gardens.tscn") as PackedScene
	if packed == null:
		push_error("LIVE_GARDEN_TOUCH_LOAD_FAILED")
		quit(1)
		return
	var world := packed.instantiate()
	root.add_child(world)
	for i in range(8):
		await physics_frame
	var player := world.get("player") as CharacterBody2D
	if player == null:
		push_error("LIVE_GARDEN_PLAYER_MISSING")
		quit(1)
		return
	var touch := root.get_node_or_null("TouchInput")
	if touch == null:
		push_error("LIVE_TOUCH_INPUT_MISSING")
		quit(1)
		return
	var directions := [
		{"name":"RIGHT","vector":Vector2.RIGHT},
		{"name":"LEFT","vector":Vector2.LEFT},
		{"name":"UP","vector":Vector2.UP},
		{"name":"DOWN","vector":Vector2.DOWN}
	]
	var failures: Array[String] = []
	for item in directions:
		touch.call("set_move_vector", item["vector"])
		var start := player.global_position
		for frame in range(60):
			await physics_frame
		var delta := player.global_position - start
		print("LIVE_TOUCH_", item["name"], " start=", start, " end=", player.global_position, " displacement=", delta, " speed=", player.velocity.length(), " collisions=", player.get_slide_collision_count())
		for ci in range(player.get_slide_collision_count()):
			var collision := player.get_slide_collision(ci)
			var collider := collision.get_collider()
			print("  BLOCKER=", collider.get_path() if collider is Node else str(collider), " point=", collision.get_position(), " normal=", collision.get_normal())
		if delta.length() < 20.0:
			failures.append(str(item["name"]))
		touch.call("release")
		player.velocity = Vector2.ZERO
		for frame in range(8):
			await physics_frame
	print("LIVE_GARDEN_TOUCH_DIRECTIONS=", 4 - failures.size(), "/4")
	if not failures.is_empty():
		push_error("LIVE_GARDEN_TOUCH_BLOCKED=" + ",".join(failures))
	world.queue_free()
	quit(1 if not failures.is_empty() else 0)
