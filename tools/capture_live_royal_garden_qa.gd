extends SceneTree

func _initialize() -> void:
	call_deferred("_capture")

func _capture() -> void:
	root.size = Vector2i(1280, 1200)
	var packed := load("res://scenes/world/castle_royal_gardens.tscn") as PackedScene
	assert(packed != null, "Playable Royal Gardens scene must load")
	var world := packed.instantiate() as Node2D
	root.add_child(world)
	var camera := Camera2D.new()
	camera.name = "QA_Camera"
	camera.position = Vector2(640, 600)
	# Use a closer overview zoom for composition inspection.
	camera.zoom = Vector2(0.62, 0.62)
	camera.enabled = true
	world.add_child(camera)
	await process_frame
	await process_frame
	await process_frame
	RenderingServer.force_draw(false)
	var image := root.get_texture().get_image()
	assert(image != null, "Live map viewport image must be available")
	var path := "C:/Users/quoth/Documents/Default Project/project-fantasy/artifacts/qa/royal_gardens_live_playable_20261119_b.png"
	var err := image.save_png(path)
	print("LIVE_PLAYABLE_CAPTURE=", path, " SIZE=", image.get_size(), " ERROR=", err)
	quit(0 if err == OK else 1)
