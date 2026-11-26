extends Node
const CP = preload("res://scripts/world/six_zone_reverie/six_zone_checkpoint.gd")
func _ready() -> void:
	call_deferred("_run")
func _run() -> void:
	var tree := get_tree()
	if not OS.get_user_data_dir().to_lower().contains("reverie_travel_test"):
		tree.quit(1)
		return
	var runner := Node.new()
	tree.root.add_child(runner)
	reparent(runner)
	GameState.quest_domain.flags["tutorial_complete"] = true
	GameState.quest_domain.flags.erase("revienna_defeated")
	tree.change_scene_to_file(CP.SCENES["StandaloneZone06"])
	await tree.scene_changed
	await tree.physics_frame
	var zone := tree.current_scene
	var player := zone.get("checkpoint_player") as CharacterBody2D
	var ramp := zone.get_node("PalaceStairElevation")
	var ok := true
	if DisplayServer.get_name() != "headless":
		var review := Camera2D.new()
		zone.add_child(review)
		review.position = Vector2(0,1500)
		review.zoom = Vector2(0.24,0.24)
		review.make_current()
		for i in range(10):
			await tree.process_frame
		await RenderingServer.frame_post_draw
		tree.root.get_texture().get_image().save_png("user://palace_overview.png")
		for side in [-1,1]:
			review.position = Vector2(1550*side,1200)
			review.zoom = Vector2(0.65,0.65)
			review.force_update_scroll()
			for i in range(5):
				await tree.physics_frame
			await RenderingServer.frame_post_draw
			tree.root.get_texture().get_image().save_png("user://palace_corner_%d.png" % side)
		player.get_node("Camera2D").make_current()
		review.queue_free()
	var arrival := zone.get_node("TransferPoints/SafeSpawnFromPreviousZone") as Marker2D
	var departure := zone.get_node("TransferPoints/ToPreviousZone") as Marker2D
	player.global_position = arrival.global_position
	player.velocity = Vector2.ZERO
	await tree.physics_frame
	var entry_clear := not player.test_move(player.global_transform, Vector2(0.1,0))
	var corridor_clear := not player.test_move(player.global_transform, (departure.global_position-arrival.global_position)*0.7)
	print("ZONE06_ENTRY clear=",entry_clear," corridor=",corridor_clear)
	ok = ok and entry_clear and corridor_clear
	var guards := zone.get_node("PalaceStairElevation/TerraceEdgeGuards") as StaticBody2D
	var space := guards.get_world_2d().direct_space_state
	for pair in [[Vector2(-1400,1050),Vector2(-1500,1050)],[Vector2(1400,1050),Vector2(1500,1050)],[Vector2(-800,1160),Vector2(-800,1250)],[Vector2(800,1160),Vector2(800,1250)]]:
		var ray := PhysicsRayQueryParameters2D.create(pair[0],pair[1],1)
		var hit := space.intersect_ray(ray)
		var protected := not hit.is_empty()
		print("TERRACE_EDGE ",pair," protected=",protected)
		ok = ok and protected
	player.position = Vector2(0, 1530)
	player.velocity = Vector2.ZERO
	player.get_node("Camera2D").reset_smoothing()
	for step in [Vector2(0,1530),Vector2(0,1345),Vector2(0,1180),Vector2(0,1115),Vector2(-800,1050)]:
		player.position = step
		player.velocity = Vector2.ZERO
		player.get_node("Camera2D").reset_smoothing()
		for i in range(12):
			await tree.physics_frame
		var blocked := player.test_move(player.global_transform,Vector2(0.1,0))
		print("PALACE_POINT ",step," elevation=",ramp.elevation_at(step)," blocked=",blocked," actual=",player.position)
		ok = ok and not blocked
		if DisplayServer.get_name() != "headless":
			await RenderingServer.frame_post_draw
			tree.root.get_texture().get_image().save_png("user://palace_%d_%d.png" % [int(step.x),int(step.y)])
	if DisplayServer.get_name() != "headless":
		for view in [Vector2(-900,1600), Vector2(900,1600)]:
			player.position = view
			player.velocity = Vector2.ZERO
			player.get_node("Camera2D").reset_smoothing()
			for i in range(12):
				await tree.physics_frame
			await RenderingServer.frame_post_draw
			tree.root.get_texture().get_image().save_png("user://palace_facade_%d.png" % int(view.x))
	player.position = Vector2(0, 1530)
	player.velocity = Vector2.ZERO
	player.get_node("Camera2D").reset_smoothing()
	await tree.physics_frame
	Input.action_press("move_up")
	for i in range(360):
		await tree.physics_frame
		if player.position.y < 1095.0:
			break
	Input.action_release("move_up")
	await tree.physics_frame
	var reached := player.position.y < 1200 and float(player.get_meta("surface_elevation", 0.0)) > 110.0
	var interact := player.get_node("InteractionComponent") as CharacterInteractionComponent
	interact.refresh_nearest()
	var boss := zone.get_node("ReviennaEncounter") as Interactable
	var in_range := interact.get_current() == boss
	var body_blocks := player.test_move(player.global_transform, Vector2(0, -120))
	print("PALACE_WALK reached=", reached, " in_range=", in_range, " boss_blocks=", body_blocks, " position=",player.position)
	ok = ok and reached and in_range and body_blocks
	if in_range:
		interact.try_interact()
		var dialog := zone.get_node("UI/Dialogue") as DialogueBox
		ok = ok and dialog.visible
		dialog.close()
	await tree.process_frame
	Input.action_press("move_down")
	for i in range(360):
		await tree.physics_frame
		if player.position.y > 1510:
			break
	Input.action_release("move_down")
	await tree.physics_frame
	var descended := player.position.y > 1490 and is_zero_approx(float(player.get_meta("surface_elevation", -1.0)))
	print("PALACE_DESCENT=",descended," position=",player.position)
	ok = ok and descended
	print("PALACE_VISUAL_TEST=",ok)
	tree.quit(0 if ok else 1)
