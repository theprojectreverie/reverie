extends SceneTree
func _initialize() -> void:
	call_deferred("_run")
func _run() -> void:
	if OS.get_environment("REVERIE_E2E_DISABLE_LOCAL_SAVE") != "1":
		quit(2)
		return
	change_scene_to_file("res://scenes/world/six_zone_reverie/individual_zones/zone_02_royal_gate_standalone.tscn")
	await scene_changed
	for i in range(5):
		await physics_frame
	var zone = current_scene
	var city = zone.get_node("Zone")
	var ground = city.get_node("GroundTiles/EditableTileMap") as TileMapLayer
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
			q.transform = Transform2D(0.0, p)
			var hits = root.world_2d.direct_space_state.intersect_shape(q)
			if not hits.is_empty():
				blocked += 1
				if examples.size()<15:
					examples.append([path.name,p,str(hits[0].collider.get_path())])
	print("LIVE PEARL tiles=",ground.get_used_cells().size()," routes=",routes.get_child_count()," samples=",samples," blocked=",blocked," missing=",missing)
	print("Blocked examples: ",examples)
	print("Market stalls=",city.find_children("MarketAsset","Node2D",true,false).size()," shops=",city.find_children("ShopAsset","Node2D",true,false).size())
	var safe = zone.get_node("TransferPoints/SafeSpawnFromPreviousZone").global_position
	q.transform = Transform2D(0.0,safe)
	print("Safe arrival clear=",root.world_2d.direct_space_state.intersect_shape(q).is_empty())
	var ok = blocked==0 and missing==0
	zone.queue_free()
	await process_frame
	root.get_node("AudioDirector").stop_all_audio_immediately()
	await create_timer(0.35).timeout
	quit(0 if ok else 1)

