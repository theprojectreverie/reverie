extends SceneTree

func _initialize():
	call_deferred("_run")
func _run():
	if OS.get_environment("REVERIE_E2E_DISABLE_LOCAL_SAVE")!="1":
		quit(2)
		return
	root.get_node("GameState").quest_domain.flags["tutorial_complete"]=true
	change_scene_to_file("res://scenes/world/village/imported_village/village_playable.tscn")
	await scene_changed
	var zone=current_scene
	var map=zone.get_node("UI/HUD/Minimap")
	var reference=load("res://tests/minimap_reference_collector.gd").new()
	var start=Time.get_ticks_msec()
	for child in zone.get_children():
		if child is Node2D: reference._collect_map_art(child,0,Color.WHITE)
	reference._zone_art.sort_custom(func(a:Dictionary,b:Dictionary)->bool:
		if a.z!=b.z: return a.z<b.z
		return a.rect.end.y<b.rect.end.y)
	var reference_ms=Time.get_ticks_msec()-start
	var valid=reference._zone_bounds==map._zone_bounds and reference._zone_art.size()==map._zone_art.size()
	var mismatch=-1
	if valid:
		for i in range(reference._zone_art.size()):
			if reference._zone_art[i]!=map._zone_art[i]:
				mismatch=i
				valid=false
				break
	print("VILLAGE_EQUIVALENCE count=",map._zone_art.size()," bounds=",map._zone_bounds," reference_ms=",reference_ms," mismatch=",mismatch," equal=",valid)
	if mismatch>=0:
		print("REFERENCE ",reference._zone_art[mismatch])
		print("OPTIMIZED ",map._zone_art[mismatch])
	reference.free()
	zone.queue_free()
	for i in range(3): await process_frame
	root.get_node("AudioDirector").stop_all_audio_immediately()
	await create_timer(0.35).timeout
	quit(0 if valid else 1)
