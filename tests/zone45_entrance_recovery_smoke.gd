extends SceneTree
func _initialize():
	call_deferred("_run")
func _run():
	if OS.get_environment("REVERIE_E2E_DISABLE_LOCAL_SAVE")!="1":
		quit(2)
		return
	var gs=root.get_node("GameState")
	gs.quest_domain.flags["tutorial_complete"]=true
	var cp=load("res://scripts/world/six_zone_reverie/six_zone_checkpoint.gd")
	var transfer=load("res://scripts/world/six_zone_reverie/zone_transfer_trigger.gd")
	var ok=true
	for id in ["StandaloneZone04","StandaloneZone05"]:
		for mode in ["fresh","invalid_checkpoint","valid_checkpoint","portal"]:
			gs.quest_domain.flags.erase("six_zone_checkpoint")
			if mode=="invalid_checkpoint":
				gs.quest_domain.flags["six_zone_checkpoint"]={"zone":id,"x":-1744,"y":620}
			if mode=="valid_checkpoint":
				gs.quest_domain.flags["six_zone_checkpoint"]={"zone":id,"x":0,"y":1450}
			transfer.pending_arrival=&"ToPreviousZone" if mode=="portal" else &""
			change_scene_to_file(cp.SCENES[id])
			await scene_changed
			for i in range(4):await physics_frame
			var zone=current_scene
			var p=zone.checkpoint_player
			var expected=Vector2(0,1450) if mode=="valid_checkpoint" else Vector2(-1600,1050)
			var tile=zone.get_node("Zone/GroundTiles/EditableTileMap")
			var terrain=tile.get_cell_source_id(tile.local_to_map(tile.to_local(p.global_position)))>=0
			var valid=p.global_position.distance_to(expected)<1.0 and terrain and cp.safe_position(zone,p.position) and not p.test_move(p.global_transform,Vector2(0.01,0))
			print("ENTRANCE ",id," ",mode," position=",p.global_position," ground=",terrain," valid=",valid)
			ok=ok and valid
	current_scene.queue_free()
	for i in range(3):await process_frame
	root.get_node("AudioDirector").stop_all_audio_immediately()
	await create_timer(0.5).timeout
	print("ENTRANCE_TEST_PASS=",ok)
	quit(0 if ok else 1)
