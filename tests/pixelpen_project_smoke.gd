extends SceneTree

func _initialize() -> void:
	for asset_id in ["royal_gate", "willow_windmill", "elderwood_ancient_tree", "forsaken_ruins_arch", "ruined_tower"]:
		var project := ProjectPacker.load_project("res://assets/pixelpen_act1/" + asset_id + ".pxpen") as PixelPenProject
		assert(project != null, "PixelPen project opens: " + asset_id)
		assert(project.canvas_size == Vector2i(64,64), "PixelPen canvas dimensions: " + asset_id)
		print("PIXELPEN_PROJECT_PASS ", asset_id, " layers=", project.active_frame.layers.size())
	print("PIXELPEN_PROJECTS_PASS 5")
	quit(0)
