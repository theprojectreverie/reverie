extends SceneTree

func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	DisplayServer.window_set_size(Vector2i(480, 860))
	var world := (load("res://scenes/world/castle_royal_gardens.tscn") as PackedScene).instantiate()
	root.add_child(world)
	for frame in range(120):
		await process_frame
	var player := world.get("player") as CharacterBody2D
	var camera := player.get_node("Camera2D") as PlayerCameraRig
	print("ACTUAL_WINDOW_SIZE=", DisplayServer.window_get_size())
	print("ROOT_VIEWPORT_SIZE=", root.size, " CAMERA_VIEWPORT=", camera.get_viewport_rect().size)
	print("PLAYER=", player.global_position, " CAMERA=", camera.global_position, " OFFSET=", camera.offset, " CURRENT=", camera.is_current(), " ACTIVE=", camera.get_viewport().get_camera_2d())
	print("WORLD_TRANSFORM=", world.global_transform, " PLAYER_LOCAL=", player.position, " CAMERA_LOCAL=", camera.position, " CAMERA_SCREEN_CENTER=", camera.get_screen_center_position())
	print("CANVAS_TRANSFORM=", camera.get_viewport().get_canvas_transform())
	print("LIMITS=", Vector4(camera.limit_left, camera.limit_top, camera.limit_right, camera.limit_bottom))
	var image := root.get_texture().get_image()
	var output := "res://artifacts/qa/royal_garden_portrait_live_engine_capture.png"
	print("IMAGE_SAVE=", image.save_png(ProjectSettings.globalize_path(output)), " SIZE=", image.get_size())
	quit(0)
