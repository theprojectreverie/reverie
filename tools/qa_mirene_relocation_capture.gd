extends SceneTree
func _initialize() -> void:
	call_deferred("run")
func run() -> void:
	root.size = Vector2i(1600, 950)
	change_scene_to_file("res://scenes/world/six_zone_reverie/individual_zones/zone_01_royal_gardens_standalone.tscn")
	await scene_changed
	var zone = current_scene
	for node in zone.get_children():
		if node is CanvasLayer: node.hide()
	var camera := Camera2D.new()
	zone.add_child(camera)
	camera.position = Vector2(0, 1598)
	camera.zoom = Vector2(0.245, 0.245)
	camera.make_current()
	await process_frame
	await process_frame
	await RenderingServer.frame_post_draw
	var image := root.get_texture().get_image()
	image.save_png("res://artifacts/qa/mirene_relocation_overview.png")
	print("CAPTURE ", image.get_size())
	quit()
