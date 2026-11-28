extends SceneTree
func _initialize() -> void:
	call_deferred("run")
func run() -> void:
	var scene := (load("res://scenes/world/six_zone_reverie/elderwood_fences/elderwood_fence_preview.tscn") as PackedScene).instantiate()
	root.add_child(scene)
	await physics_frame
	await physics_frame
	var expected := {"woodland_corner":5,"woodland_enclosure":8,"woodland_post":1}
	for name in expected:
		var prop: Node2D = scene.get_node(name)
		var art: Sprite2D = prop.get_node("Artwork")
		var body: StaticBody2D = prop.get_node("Body")
		assert(art.texture != null and art.texture_filter == CanvasItem.TEXTURE_FILTER_NEAREST)
		assert(body.collision_layer == 1 and body.collision_mask == 0)
		assert(body.get_child_count() == expected[name])
		for node in body.get_children():
			assert(node is CollisionPolygon2D and node.polygon.size() == 4 and not node.disabled)
		var query := PhysicsPointQueryParameters2D.new()
		query.position = prop.global_position
		query.collision_mask = 1
		var hits: Array[Dictionary] = prop.get_world_2d().direct_space_state.intersect_point(query)
		assert(hits.any(func(hit): return hit.collider == body))
	print("ELDERWOOD FENCE PREFABS: 3 textures, 14 polygons, 3 ground-anchor physics queries PASS")
	scene.queue_free()
	await process_frame
	quit(0)


