extends SceneTree
func _initialize() -> void:
	call_deferred("_run")
func _run() -> void:
	var packed := load("res://scenes/world/castle_royal_gardens.tscn") as PackedScene
	assert(packed != null)
	var world := packed.instantiate() as Node2D
	root.add_child(world)
	await process_frame
	var ground := world.get_node_or_null("Terrain/TilemapCandidate/BaseGround") as TileMapLayer
	assert(ground != null)
	var cells := ground.get_used_cells()
	var min_x := 999999
	var min_y := 999999
	var max_x := -999999
	var max_y := -999999
	for cell in cells:
		min_x = mini(min_x, cell.x)
		min_y = mini(min_y, cell.y)
		max_x = maxi(max_x, cell.x)
		max_y = maxi(max_y, cell.y)
	var holes: Array[Vector2i] = []
	for y in range(min_y, max_y + 1):
		for x in range(min_x, max_x + 1):
			if ground.get_cell_source_id(Vector2i(x, y)) < 0:
				holes.append(Vector2i(x, y))
	print("BAKED_GROUND_AUDIT: cells=%d bounds=(%d,%d)-(%d,%d) holes=%d" % [cells.size(), min_x, min_y, max_x, max_y, holes.size()])
	print("KNOWN_HOLE_12_-35: source_id=%d" % ground.get_cell_source_id(Vector2i(12, -35)))
	var shown := 0
	for cell in holes:
		if shown >= 80:
			break
		print("GROUND_HOLE: ", cell)
		shown += 1
	world.queue_free()
	await process_frame
	quit(0)
