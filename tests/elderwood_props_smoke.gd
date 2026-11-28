extends SceneTree
func _initialize() -> void:
	call_deferred("run")
func run() -> void:
	var scene := (load("res://scenes/world/six_zone_reverie/elderwood_props/elderwood_props_preview.tscn") as PackedScene).instantiate()
	root.add_child(scene)
	await physics_frame
	await physics_frame
	var solids := 0
	for child in scene.get_children():
		var prop := child as Node2D
		var art := prop.get_node("Artwork") as Sprite2D
		assert(art.texture != null and art.texture_filter == CanvasItem.TEXTURE_FILTER_NEAREST)
		var body := prop.get_node_or_null("Body") as StaticBody2D
		if prop.name == &"mossy_stepping_stones":
			assert(body == null and art.z_index == -1)
			continue
		assert(body != null and body.collision_layer == 1)
		var footprint := body.get_node("Footprint") as CollisionPolygon2D
		assert(footprint.polygon.size() == 4 and not footprint.disabled)
		var center := Vector2.ZERO
		for point in footprint.polygon: center += point
		center /= footprint.polygon.size()
		var q := PhysicsPointQueryParameters2D.new()
		q.position = footprint.to_global(center)
		q.collision_mask = 1
		var hits: Array[Dictionary] = prop.get_world_2d().direct_space_state.intersect_point(q)
		assert(hits.any(func(hit): return hit.collider == body))
		solids += 1
	assert(scene.get_child_count() == 8 and solids == 7)
	print("ELDERWOOD PROPS: 8 textures, 7 solid footprints and 1 walkable tile PASS")
	scene.queue_free()
	await process_frame
	quit(0)

