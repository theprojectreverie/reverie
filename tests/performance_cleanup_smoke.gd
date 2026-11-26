extends Node
var ok := true
func check(value: bool, label: String) -> void:
	print("PERF ",label,"=",value)
	ok = ok and value
func _ready() -> void:
	if OS.get_environment("REVERIE_E2E_DISABLE_LOCAL_SAVE")!="1":
		get_tree().quit(2)
		return
	GameState.quest_domain.flags["tutorial_complete"]=true
	var hud = load("res://scenes/ui/hud.tscn").instantiate()
	add_child(hud)
	await get_tree().process_frame
	var chip_ids: Array = []
	for c in hud._currency_box.get_children(): chip_ids.append(c.get_instance_id())
	var party_ids: Array = []
	for c in hud._party_box.get_children(): party_ids.append(c.get_instance_id())
	for i in range(100):
		hud.refresh_currency()
		hud.refresh_party()
	var chips_after: Array = []
	for c in hud._currency_box.get_children(): chips_after.append(c.get_instance_id())
	var party_after: Array = []
	for c in hud._party_box.get_children(): party_after.append(c.get_instance_id())
	check(chip_ids==chips_after and not chip_ids.is_empty(),"100_wallet_refreshes_reuse_nodes")
	check(party_ids==party_after and party_ids.size()>1,"100_party_refreshes_reuse_nodes")
	GameState.inventory_domain.add_currency("gold",1)
	check(hud._currency_box.get_child(0).get_instance_id()!=chip_ids[0],"changed_wallet_rebuilds")
	var instance: CharacterInstance = GameState.roster_domain.party_instances()[0]
	instance.level+=1
	hud.refresh_party()
	check(hud._party_box.get_child_count()==party_ids.size() and hud._party_box.get_child(1).get_instance_id()!=party_ids[1],"changed_party_rebuilds_without_duplicates")
	hud.queue_free()
	await get_tree().process_frame
	AudioDirector.stop_all_audio_immediately()
	AudioDirector.play_sfx("ui_crystal_click")
	await get_tree().create_timer(2.0).timeout
	var clear := true
	for p in AudioDirector._sfx_players:
		if p.stream != null or p.playing: clear=false
	check(clear,"finished_sfx_releases_stream")
	AudioDirector.stop_all_audio_immediately()
	await get_tree().create_timer(0.35).timeout
	var manifest: Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://resources/data/six_zone_expeditions.json"))
	var paths: Array=["res://scenes/world/village/imported_village/village_playable.tscn"]
	for key in manifest: paths.append(str(manifest[key].scene))
	var timings: Array = []
	var orphan_before := int(Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT))
	for cycle in range(2):
		for path in paths:
			var start:=Time.get_ticks_msec()
			var zone=(load(path) as PackedScene).instantiate()
			add_child(zone)
			for f in range(3): await get_tree().process_frame
			var ms:=Time.get_ticks_msec()-start
			timings.append(ms)
			var zone_ref: WeakRef=weakref(zone)
			var player_ref: WeakRef=weakref(zone.get("checkpoint_player"))
			check(get_tree().get_nodes_in_group("player").size()==1,"single_player_"+str(zone.name))
			print("PERF_LOAD ",cycle+1," ",zone.name," ms=",ms)
			zone.queue_free()
			for f in range(3): await get_tree().process_frame
			check(zone_ref.get_ref()==null and player_ref.get_ref()==null,"freed_zone_"+str(path.get_file()))
	AudioDirector.stop_all_audio_immediately()
	await get_tree().create_timer(0.35).timeout
	var orphan_after := int(Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT))
	print("PERF_ORPHANS before=",orphan_before," after=",orphan_after)
	check(orphan_after<=orphan_before,"no_orphan_growth")
	print("PERF_PASS=",ok)
	get_tree().quit(0 if ok else 1)
