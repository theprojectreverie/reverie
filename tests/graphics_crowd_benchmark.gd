extends SceneTree
# Synthetic crowd in an existing authored zone, using real remote avatar scenes.
# Headless CPU measurements are NOT GPU or phone frame-rate measurements.
func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	if OS.get_environment("REVERIE_E2E_DISABLE_LOCAL_SAVE") != "1":
		quit(2)
		return
	var state := root.get_node("GameState")
	var graphics := root.get_node("GraphicsSettings")
	state.quest_domain.flags["tutorial_complete"] = true
	state.quest_domain.flags["village_gerald_defeated"] = true
	graphics.apply_preferences(2, 60)
	var path := "res://scenes/world/six_zone_reverie/individual_zones/zone_01_royal_gardens_standalone.tscn"
	assert(change_scene_to_file(path) == OK)
	await scene_changed
	for i in range(10):
		await process_frame
	var sync: Node = load("res://scripts/online/coop_world_sync_component.gd").new()
	current_scene.add_child(sync)
	var layer := Node2D.new()
	current_scene.add_child(layer)
	layer.top_level = true
	layer.global_position = Vector2.ZERO
	sync.remote_root = layer
	sync.entities = layer
	sync.active_region_id = "six_zone_royal_gardens"
	sync.local_player = current_scene.get("checkpoint_player")
	var center: Vector2 = sync.local_player.global_position
	var origin := layer.get_global_transform_with_canvas().affine_inverse() * (root.get_visible_rect().size * 0.5)
	var peers: Array[Node] = []
	var starts: Array[Vector2] = []
	for i in range(100):
		var target := origin + Vector2(float(i%4)*20.0,float(i/4)*20.0) if i<12 else center+Vector2(20000.0+100.0*i,20000.0)
		starts.append(target)
		var avatar: Node = sync.call("_ensure_remote","benchmark-%d"%i,"Adventurer %d"%i,target)
		assert(avatar != null)
		peers.append(avatar)
	for mode in [2, 1, 0, 2]:
		graphics.apply_preferences(mode,60)
		for i in range(peers.size()):
			peers[i].position = starts[i]
			peers[i].target_position = starts[i]
			peers[i]._refresh_presentation_budget()
		for i in range(60):
			await process_frame
		var times: Array[float] = []
		var start := Time.get_ticks_usec()
		for f in range(180):
			if f%12 == 0:
				for i in range(peers.size()):
					peers[i].target_position = starts[i]+Vector2(float((f/12)%2)*10.0,0.0)
			await process_frame
			times.append(Performance.get_monitor(Performance.TIME_PROCESS)*1000.0)
		var elapsed := float(Time.get_ticks_usec()-start)/1000000.0
		times.sort()
		var visible_count := 0
		var uncapped_count := 0
		var near_interval := -1.0
		var far_interval := -1.0
		for i in range(peers.size()):
			var peer: Node = peers[i]
			peer._refresh_presentation_budget()
			if peer.visible:
				visible_count += 1
			var interval: float = peer.visual.animation_runtime_component.presentation_interval
			if interval == 0.0:
				uncapped_count += 1
			if i==0:
				near_interval=interval
			if i==99:
				far_interval=interval
		assert(visible_count == (100 if mode==2 else 12))
		assert(uncapped_count == (100 if mode==2 else 0))
		assert(is_equal_approx(near_interval,0.0 if mode==2 else (1.0/30.0 if mode==1 else 1.0/15.0)))
		assert(is_equal_approx(far_interval,0.0 if mode==2 else (0.125 if mode==1 else 0.25)))
		var info := {"quality":mode,"samples":times.size(),"elapsed_seconds":elapsed,"cpu_process_p50_ms":times[89],"cpu_process_p95_ms":times[170],"visible":visible_count,"full_rate_avatars":uncapped_count,"near_interval":near_interval,"far_interval":far_interval,"memory_mib":Performance.get_monitor(Performance.MEMORY_STATIC)/1048576.0}
		print("CROWD_BENCHMARK "+JSON.stringify(info))
	sync.call("_clear_remote_players")
	await process_frame
	assert(sync.remote_players.is_empty())
	current_scene.queue_free()
	await process_frame
	root.get_node("AudioDirector").stop_all_audio_immediately()
	await create_timer(0.5).timeout
	print("CROWD_BENCHMARK_PASS")
	quit()
