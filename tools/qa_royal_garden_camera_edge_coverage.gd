extends SceneTree

const WORLD_SCENE := "res://scenes/world/castle_royal_gardens.tscn"
const VIEW_SIZES := [Vector2i(1280, 720), Vector2i(480, 860), Vector2i(720, 720)]
const SCREEN_POSITIONS := [
	Vector2(1000, 700),
	Vector2(640, 900),
	Vector2(400, 1200),
	Vector2(1600, 1200),
	Vector2(400, 1800),
	Vector2(1600, 1800),
]

func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var all_passed := true
	for view_size in VIEW_SIZES:
		var base_width := float(ProjectSettings.get_setting("display/window/size/viewport_width"))
		var logical_view_size := Vector2i(roundi(base_width), roundi(base_width * float(view_size.y) / float(view_size.x)))
		var viewport := SubViewport.new()
		viewport.size = logical_view_size
		viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
		root.add_child(viewport)
		var world := (load(WORLD_SCENE) as PackedScene).instantiate()
		viewport.add_child(world)
		for frame in range(8):
			await physics_frame
		var player := world.get("player") as CharacterBody2D
		var camera := player.get_node("Camera2D") as PlayerCameraRig
		var ground := world.get_node("Terrain/TilemapCandidate/BaseGround") as TileMapLayer
		camera.position_smoothing_enabled = false
		var portrait := float(view_size.x) / float(view_size.y) < PlayerCameraRig.PORTRAIT_ASPECT_THRESHOLD
		camera.update_follow_offset(1.0, Vector2.ZERO, 0.0)
		# A real window uses canvas_items + aspect=expand: logical camera width
		# stays at the project base width while its logical height grows in portrait.
		var camera_view_size := Vector2(logical_view_size)
		var failed_samples: Array[String] = []
		for screen_position in SCREEN_POSITIONS:
			player.global_position = world.to_global(screen_position)
			camera.reset_smoothing()
			await process_frame
			var inverse := camera.get_viewport().get_canvas_transform().affine_inverse()
			var viewport_corners := [
				inverse * Vector2.ZERO,
				inverse * Vector2(camera_view_size.x, 0),
				inverse * Vector2(0, camera_view_size.y),
				inverse * camera_view_size,
			]
			for corner_index in range(viewport_corners.size()):
				var cell := ground.local_to_map(ground.to_local(viewport_corners[corner_index]))
				if ground.get_cell_source_id(cell) < 0:
					var tile_center: Vector2 = world.to_local(ground.to_global(ground.map_to_local(cell)))
					failed_samples.append("player=%s corner=%d point=%s cell=%s tile_center=%s" % [screen_position, corner_index, world.to_local(viewport_corners[corner_index]), cell, tile_center])
		print("CAMERA_EDGE_COVERAGE: %s %s -> %d/%d corners covered" % [
			"portrait" if portrait else ("landscape" if view_size.x > view_size.y else "square"),
			view_size,
			4 * SCREEN_POSITIONS.size() - failed_samples.size(),
			4 * SCREEN_POSITIONS.size(),
		])
		for failure in failed_samples:
			print("CAMERA_EDGE_GAP: ", failure)
		if not failed_samples.is_empty():
			all_passed = false
		world.queue_free()
		viewport.queue_free()
		await process_frame
	if not all_passed:
		push_error("CAMERA_EDGE_COVERAGE_FAILED")
		quit(1)
		return
	print("ROYAL_GARDEN_CAMERA_EDGE_COVERAGE_OK")
	quit(0)
