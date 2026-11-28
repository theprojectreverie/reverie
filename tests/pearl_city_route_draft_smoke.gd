extends SceneTree
func _initialize() -> void:
	call_deferred("_run")
func _run() -> void:
	var packed = load("res://scenes/world/six_zone_reverie/pearl_city_draft/pearl_city_playable_preview.tscn")
	if packed == null:
		quit(2)
		return
	var city = packed.instantiate()
	root.add_child(city)
	await physics_frame
	await physics_frame
	var ground = city.get_node("DraftGround") as TileMapLayer
	var routes = city.get_node("WalkableRoutes")
	var shape = CircleShape2D.new()
	shape.radius = 18
	var q = PhysicsShapeQueryParameters2D.new()
	q.shape = shape
	q.collision_mask = 1
	q.collide_with_areas = false
	var samples = 0
	var blocked = 0
	var missing = 0
	var examples = []
	for child in routes.get_children():
		var path = child as Path2D
		for i in range(0, int(ceil(path.curve.get_baked_length()/16.0))+1):
			var p = path.to_global(path.curve.sample_baked(minf(i*16.0, path.curve.get_baked_length())))
			samples += 1
			if ground.get_cell_source_id(ground.local_to_map(ground.to_local(p))) < 0:
				missing += 1
				print("MISSING: ",path.name," ",p," cell=",ground.local_to_map(ground.to_local(p)))
			q.transform = Transform2D(0.0, p)
			var hits = root.world_2d.direct_space_state.intersect_shape(q)
			if not hits.is_empty():
				blocked += 1
				if examples.size()<10:
					examples.append([path.name,p,str(hits[0].collider.get_path())])
	print("PEARL DRAFT cells=",ground.get_used_cells().size()," routes=",routes.get_child_count()," samples=",samples," blocked=",blocked," no_ground=",missing)
	print("Blocked examples: ",examples)
	print("Market sprites=",city.find_children("MarketAsset","Node2D",true,false).size()," park props=",city.get_node("CentralPark").find_children("DraftAsset", "Node2D", true, false).size())
	city.queue_free()
	await process_frame
	quit(0 if blocked==0 and missing==0 else 1)

