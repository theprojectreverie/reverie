extends SceneTree
func _initialize():
	call_deferred("_run")
func _run():
	if OS.get_environment("REVERIE_E2E_DISABLE_LOCAL_SAVE")!="1" or DisplayServer.get_name()=="headless":
		quit(2)
		return
	var output=OS.get_environment("QA_MAP_OUTPUT")
	var manifest=JSON.parse_string(FileAccess.get_file_as_string("res://resources/data/six_zone_expeditions.json"))
	var paths=["res://scenes/world/village/imported_village/village_playable.tscn"]
	for key in manifest: paths.append(str(manifest[key].scene))
	var gs=root.get_node("GameState")
	gs.quest_domain.flags["tutorial_complete"]=true
	var transfer=load("res://scripts/world/six_zone_reverie/zone_transfer_trigger.gd")
	for i in range(paths.size()):
		var path=paths[i]
		transfer.pending_arrival=&"ToPreviousZone" if i>=2 else &""
		change_scene_to_file(path)
		await scene_changed
		for f in range(75):await physics_frame
		var zone=current_scene
		var player=zone.get("checkpoint_player")
		player.input_enabled=false
		player.velocity=Vector2.ZERO
		var camera=player.get_node("Camera2D")
		camera.reset_smoothing()
		camera.force_update_scroll()
		for f in range(10):await process_frame
		await RenderingServer.frame_post_draw
		var view=root.get_visible_rect()
		var screen_point=root.get_canvas_transform()*player.global_position
		var safe=view.grow(-view.size.y*0.06).has_point(screen_point)
		print("CAMERA_FRAME ",zone.name," ",view.size," point=",screen_point," safe=",safe)
		if not safe:
			quit(1)
			return
		var img=root.get_texture().get_image()
		var result=img.save_png(output.path_join(str(zone.name)+".png"))
		print("MAP_REVIEW ",zone.name," ",img.get_size()," zoom=",camera.zoom," player=",player.global_position," capture=",result)
		if result!=OK:
			quit(1)
			return
	current_scene.queue_free()
	for i in range(3):await process_frame
	root.get_node("AudioDirector").stop_all_audio_immediately()
	await create_timer(0.5).timeout
	print("MAP_REVIEW_ALL_PASS")
	quit(0)
