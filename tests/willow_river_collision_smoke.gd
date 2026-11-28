extends SceneTree

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	if OS.get_environment("REVERIE_E2E_DISABLE_LOCAL_SAVE") != "1":
		quit(2)
		return
	var game_state := root.get_node("GameState")
	game_state.quest_domain.flags["tutorial_complete"] = true
	game_state.quest_domain.flags.erase("six_zone_checkpoint")
	change_scene_to_file("res://scenes/world/six_zone_reverie/individual_zones/zone_03_willow_fields_standalone.tscn")
	await scene_changed
	for i in range(8):
		await physics_frame
	var zone := current_scene.get_node("Zone")
	var river := zone.get_node("WillowStream/RiverCollision")
	var space: PhysicsDirectSpaceState2D = zone.get_world_2d().direct_space_state
	var failures: Array[String] = []
	var water_points := [Vector2(500, 1200), Vector2(880, 1550), Vector2(1400, 2110), Vector2(1570, 2280)]
	for point in water_points:
		var query := PhysicsPointQueryParameters2D.new()
		query.position = point
		query.collision_mask = 1
		var hits: Array[Dictionary] = space.intersect_point(query, 16)
		var body_name := "UpstreamWater" if point.y < 1677.0 else "DownstreamWater"
		if not hits.any(func(hit: Dictionary) -> bool: return hit.collider == river.get_node(body_name)):
			failures.append("water collision missing at %s" % point)
	var player_shape: Shape2D = current_scene.checkpoint_player.get_node("CollisionShape2D").shape
	var bridge_query := PhysicsShapeQueryParameters2D.new()
	bridge_query.shape = player_shape
	bridge_query.collision_mask = 1
	bridge_query.transform = Transform2D(0.0, Vector2(1169, 1594))
	var bridge_hits: Array[Dictionary] = space.intersect_shape(bridge_query, 8)
	if not bridge_hits.is_empty():
		print("BRIDGE CENTER COLLIDERS ", bridge_hits.map(func(hit: Dictionary) -> String: return str(hit.collider.name)))
		failures.append("bridge deck approach player footprint is occupied")
	var bank_query := PhysicsShapeQueryParameters2D.new()
	bank_query.shape = player_shape
	bank_query.collision_mask = 1
	bank_query.transform = Transform2D(0.0, Vector2(370, 1190))
	if not space.intersect_shape(bank_query, 8).is_empty():
		failures.append("upstream bank approach is blocked")
	for transfer_point in [Vector2(-2720, 1360), Vector2(3008, 1776)]:
		var transfer_query := PhysicsShapeQueryParameters2D.new()
		transfer_query.shape = player_shape
		transfer_query.collision_mask = 1
		transfer_query.transform = Transform2D(0.0, transfer_point + Vector2(0, -10))
		var transfer_hits: Array[Dictionary] = space.intersect_shape(transfer_query, 8)
		if not transfer_hits.is_empty():
			failures.append("transfer approach is blocked at %s by %s" % [transfer_point, transfer_hits.map(func(hit: Dictionary) -> String: return str(hit.collider.name))])
	print("WILLOW RIVER COLLISION water_samples=", water_points.size(), " failures=", failures)
	current_scene.queue_free()
	for i in range(3):
		await process_frame
	root.get_node("AudioDirector").stop_all_audio_immediately()
	await create_timer(0.35).timeout
	quit(0 if failures.is_empty() else 1)
