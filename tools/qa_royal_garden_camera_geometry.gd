extends SceneTree

func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var packed := load("res://scenes/world/castle_royal_gardens.tscn") as PackedScene
	assert(packed != null)
	var world := packed.instantiate() as Node2D
	root.add_child(world)
	for frame in range(8):
		await physics_frame
	var player := world.get("player") as CharacterBody2D
	var camera := player.get_node("Camera2D") as Camera2D
	var ground := world.get_node("Terrain/TilemapCandidate/BaseGround") as TileMapLayer
	print("WORLD_TRANSFORM=", world.global_transform)
	print("PLAYER_GLOBAL=", player.global_position)
	print("CAMERA_GLOBAL=", camera.global_position, " POSITION=", camera.position, " OFFSET=", camera.offset)
	print("CAMERA_LIMITS=", camera.limit_left, ",", camera.limit_top, " -> ", camera.limit_right, ",", camera.limit_bottom)
	print("VIEWPORT_SIZE=", camera.get_viewport_rect().size)
	print("GROUND_USED_RECT=", ground.get_used_rect(), " TILE_SIZE=", ground.tile_set.tile_size)
	var rect := ground.get_used_rect()
	var corners := [
		ground.map_to_local(rect.position),
		ground.map_to_local(rect.position + Vector2i(rect.size.x - 1, 0)),
		ground.map_to_local(rect.position + Vector2i(0, rect.size.y - 1)),
		ground.map_to_local(rect.position + rect.size - Vector2i.ONE)
	]
	for corner in corners:
		print("GROUND_CORNER_WORLD=", ground.to_global(corner))
	world.queue_free()
	quit(0)
