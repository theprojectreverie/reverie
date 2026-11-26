extends SceneTree
func _initialize():
	call_deferred("_run")
func _run():
	var paths: Array = []
	var data=JSON.parse_string(FileAccess.get_file_as_string("res://resources/data/six_zone_expeditions.json"))
	for key in data: paths.append(str(data[key].scene))
	var warm_scene = [load("res://scripts/game/game_overlay_router_component.gd"),load("res://scripts/world/six_zone_reverie/standalone_zone_controller.gd"),load("res://scripts/game/game_combat_router_component.gd"),load("res://scripts/world/six_zone_reverie/zone_ui_binding.gd"),load("res://scenes/ui/game_ui.tscn")]
	assert(warm_scene.all(func(r):return r!=null))
	for cycle in range(2):
		for path in paths:
			var e=ResourceLoader.load_threaded_request(path,"PackedScene",false)
			assert(e==OK)
			while ResourceLoader.load_threaded_get_status(path)==ResourceLoader.THREAD_LOAD_IN_PROGRESS:
				await process_frame
			var packed=ResourceLoader.load_threaded_get(path)
			assert(packed is PackedScene)
			packed=null
			await process_frame
	warm_scene=null
	for i in range(5): await process_frame
	print("THREADED_RESOURCE_ONLY PASS")
	quit(0)
