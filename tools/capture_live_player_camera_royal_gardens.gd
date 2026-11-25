extends SceneTree

func _initialize() -> void:
	call_deferred("_capture")

func _capture() -> void:
	var packed := load("res://scenes/world/castle_royal_gardens.tscn") as PackedScene
	assert(packed != null)
	var world := packed.instantiate()
	root.add_child(world)
	for frame in range(12):
		await physics_frame
		await process_frame
	var player := world.get("player") as CharacterBody2D
	assert(player != null)
	var camera := player.get_node("Camera2D") as Camera2D
	assert(camera != null)
	camera.make_current()
	camera.offset = Vector2(0, -240)
	await process_frame
	await process_frame
	RenderingServer.force_draw(false)
	var image := root.get_texture().get_image()
	var output := "res://artifacts/qa/royal_gardens_player_camera_offset_trial_20261119.png"
	var err := image.save_png(output)
	var flora := world.get_node_or_null("ExpansionBuilder/ExpansionFlora")
	var props := world.get_node_or_null("ExpansionBuilder/ExpansionProps")
	print("PLAYER_CAMERA_CAPTURE=", output, " ERROR=", err, " VIEWPORT=", image.get_size())
	print("PLAYER_CAMERA_ZOOM=", camera.zoom, " CAMERA_POSITION=", camera.global_position, " PLAYER_POSITION=", player.global_position)
	print("EXPANSION_FLORA_VISIBLE=", flora.visible if flora != null else "MISSING", " PROPS_VISIBLE=", props.visible if props != null else "MISSING")
	quit(0 if err == OK else 1)
