extends SceneTree
func _initialize() -> void:
	call_deferred("_capture")
func _capture() -> void:
	var root: Node = load("res://scenes/world/castle_gardens/components/reverie_royal_gardens_full_preview.tscn").instantiate()
	get_root().size = Vector2i(1280, 1200)
	root.get_node("PreviewCamera").position = Vector2(640, 600)
	root.get_node("PreviewCamera").zoom = Vector2(0.85, 0.85)
	get_root().add_child(root)
	await process_frame
	await process_frame
	var image := get_root().get_texture().get_image()
	var err := image.save_png("C:/Users/quoth/Documents/Default Project/project-fantasy/royal_garden_preview_qa.png")
	print("PREVIEW_CAPTURE_ERROR=", err, " SIZE=", image.get_size())
	quit(0 if err == OK else 1)

