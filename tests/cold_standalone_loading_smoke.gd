extends SceneTree
func _initialize():
	call_deferred("_run")
func _run():
	if OS.get_environment("REVERIE_E2E_DISABLE_LOCAL_SAVE")!="1":
		quit(2)
		return
	var manifest=JSON.parse_string(FileAccess.get_file_as_string("res://resources/data/six_zone_expeditions.json"))
	var name=OS.get_environment("QA_COLD_REGION")
	var path="res://scenes/world/village/imported_village/village_playable.tscn" if name=="village" else str(manifest[name].scene)
	var loader=load("res://scripts/ui/components/loading_resource_component.gd").new()
	root.add_child(loader)
	loader.minimum_display_seconds=0.0
	var results: Dictionary={"packed":null,"failed":false}
	loader.scene_loaded.connect(func(packed):results.packed=packed)
	loader.load_failed.connect(func():results.failed=true)
	loader.begin(path)
	var deadline=Time.get_ticks_msec()+30000
	while results.packed==null and not results.failed and Time.get_ticks_msec()<deadline:
		await process_frame
	if results.packed==null:
		printerr("COLD_LOAD_FAIL ",name)
		loader.queue_free()
		quit(1)
		return
	root.get_node("GameState").quest_domain.flags["tutorial_complete"]=true
	change_scene_to_packed(results.packed)
	await scene_changed
	for i in range(5):await process_frame
	var ok=current_scene.get("checkpoint_player")!=null and current_scene.get_node_or_null("UI/HUD")!=null and current_scene.get_node("OverlayRouter").has_method("open_screen") and loader._shared_dependencies.is_empty()
	print("COLD_LOAD ",name," ready=",ok)
	current_scene.queue_free()
	loader.queue_free()
	results.packed=null
	for i in range(3):await process_frame
	root.get_node("AudioDirector").stop_all_audio_immediately()
	await create_timer(0.5).timeout
	quit(0 if ok else 1)
