extends SceneTree

class LocalStub:
	extends Node2D
	var network_recovery_paused := true
	func set_network_recovery_paused(value: bool) -> void:
		network_recovery_paused = value

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	if OS.get_environment("REVERIE_E2E_DISABLE_LOCAL_SAVE") != "1":
		quit(2)
		return
	var sync = load("res://scripts/online/coop_world_sync_component.gd").new()
	root.add_child(sync)
	sync.set_process(false)
	var layer := Node2D.new()
	root.add_child(layer)
	var local := LocalStub.new()
	root.add_child(local)
	sync.remote_root = layer
	sync.entities = layer
	sync.local_player = local
	sync.active_region_id = "six_zone_royal_gardens"
	var members: Array[Dictionary] = [{"playerId":"local","x":20.0,"y":30.0}]
	for i in range(100):
		members.append({"playerId":"peer-%d"%i,"name":"Adventurer %d"%i,"title":"Dawn Wanderer","x":100.0+i,"y":200.0})
	var began := Time.get_ticks_usec()
	sync._on_persistent_world_event({"type":"world_joined","serverId":"budget-qa","playerId":"local","interestWindows":true,"eventSequence":1,"members":members})
	var stage_ms := float(Time.get_ticks_usec()-began)/1000.0
	assert(sync._snapshot_ready and not local.network_recovery_paused and local.position==Vector2(20,30))
	assert(sync.remote_players.is_empty() and sync._pending_remote_members.size()==100)
	var warmup_started := Time.get_ticks_usec()
	while sync._remote_sheet_loading and Time.get_ticks_usec()-warmup_started<5000000:
		await process_frame
	assert(not sync._remote_sheet_loading and sync._remote_sheet != null)
	var prefetch_ms := float(Time.get_ticks_usec()-warmup_started)/1000.0
	assert(sync.remote_players.is_empty())
	var peak_batch := 0
	var peak_ms := 0.0
	var frames := 0
	began = Time.get_ticks_usec()
	sync._drain_remote_admissions()
	peak_ms=maxf(peak_ms,float(Time.get_ticks_usec()-began)/1000.0)
	var cold_batch_ms := peak_ms
	var warm_batch_times: Array[float] = []
	var initial_count: int = sync.remote_players.size()
	assert(initial_count>0 and initial_count<=4)
	peak_batch=initial_count
	var latest: Array[Dictionary] = []
	for i in range(1,100):
		latest.append({"playerId":"peer-%d"%i,"name":"Latest %d"%i,"title":"Dawn Wanderer","x":300.0+i,"y":400.0})
	sync._on_persistent_world_event({"type":"world_position_window","fromSequence":2,"sequence":2,"members":latest})
	assert(not sync.remote_players.has("peer-0") and not sync._pending_remote_members.has("peer-0"))
	sync._on_persistent_world_event({"type":"player_titles","players":[{"playerId":"peer-99","title":"Arena Sovereign"}]})
	sync._on_persistent_world_event({"type":"position","playerId":"peer-99","x":888.0,"y":999.0,"sequence":3})
	sync._on_persistent_world_event({"type":"player_left","playerId":"peer-98","sequence":4})
	assert(not sync._pending_remote_members.has("peer-98"))
	while not sync._pending_remote_members.is_empty() and frames<120:
		var old_size: int = sync.remote_players.size()
		began=Time.get_ticks_usec()
		sync._drain_remote_admissions()
		var batch_ms := float(Time.get_ticks_usec()-began)/1000.0
		warm_batch_times.append(batch_ms)
		peak_ms=maxf(peak_ms,batch_ms)
		var batch: int = sync.remote_players.size()-old_size
		assert(batch>0 and batch<=4)
		peak_batch=maxi(peak_batch,batch)
		frames+=1
		await process_frame
	assert(sync._pending_remote_members.is_empty() and sync.remote_players.size()==98)
	assert(sync.remote_players["peer-99"].target_position==Vector2(888,999))
	assert(sync.remote_players["peer-99"].display_title=="Arena Sovereign")
	assert(sync.remote_players["peer-50"].target_position==Vector2(350,400))
	assert(sync._persistent_last_sequence==4)
	# Recovery, then a replacement snapshot and an immediate clear.
	var more: Array[Dictionary] = [{"playerId":"local","x":20.0,"y":30.0}]
	for i in range(100):
		more.append({"playerId":"replacement-%d"%i,"x":100.0,"y":200.0})
	sync._on_persistent_world_event({"type":"world_joined","serverId":"budget-qa","playerId":"local","interestWindows":true,"eventSequence":5,"members":more})
	assert(sync._pending_remote_members.size()==100)
	sync._clear_remote_players()
	assert(sync._pending_remote_members.is_empty() and sync.remote_players.is_empty())
	# A map teardown invalidates an in-flight completion without cancelling
	# the loader's responsibility to consume the resource request.
	sync._request_remote_sheet()
	var abandoned_generation: int = sync._remote_sheet_generation
	sync._clear_remote_players()
	assert(sync._remote_sheet_generation != abandoned_generation)
	var deadline := Time.get_ticks_usec()+5000000
	while root.get_node_or_null("RemoteSheetPrefetch") != null and Time.get_ticks_usec()<deadline:
		await process_frame
	assert(root.get_node_or_null("RemoteSheetPrefetch") == null)
	assert(sync._remote_sheet == null and not sync._remote_sheet_loading)
	await process_frame
	warm_batch_times.sort()
	print("REMOTE_ADMISSION_BUDGET_PASS "+JSON.stringify({"initial_remote_members":100,"stage_ms":stage_ms,"peak_spawn_batch":peak_batch,"peak_batch_ms":peak_ms,"first_prefetched_batch_ms":cold_batch_ms,"prefetch_ms":prefetch_ms,"warm_batch_p50_ms":warm_batch_times[floori(warm_batch_times.size()*0.5)],"warm_batch_p95_ms":warm_batch_times[ceili(warm_batch_times.size()*0.95)-1],"drain_frames":frames,"latest_coordinates":true,"departures_cancelled":true,"local_recovery":true}))
	sync.queue_free()
	local.queue_free()
	await process_frame
	quit()
