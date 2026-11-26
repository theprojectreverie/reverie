extends Node
func _ready() -> void:
	call_deferred("run")
func fail(reason: String) -> void:
	print("FAIL ",reason)
	get_tree().quit(1)
func run() -> void:
	AuthGateway.api_base_url = OS.get_environment("QA_API")
	MultiplayerGateway.websocket_url = OS.get_environment("QA_WS")
	if AuthGateway.login(OS.get_environment("QA_NAME"), OS.get_environment("QA_PASSWORD")) != OK:
		fail("login")
		return
	var result: Array = await AuthGateway.auth_result
	if not bool(result[1]):
		fail("auth")
		return
	GameState.quest_domain.flags["tutorial_complete"] = true
	var old_quest := GameState.quest_domain.quest_state("cassien_resurrection")
	var old_gold := GameState.inventory_domain.currency("gold")
	MultiplayerGateway.standalone_expedition_id = OS.get_environment("QA_LOBBY")
	MultiplayerGateway.standalone_expedition_region = "six_zone_forsaken_ruins"
	var zone = load("res://scenes/world/six_zone_reverie/individual_zones/zone_05_forsaken_ruins_standalone.tscn").instantiate()
	add_child(zone)
	var sync = zone.get_node("CoopWorldSync")
	var deadline := Time.get_ticks_msec()+12000
	while not sync._snapshot_ready or sync.remote_players.size()!=1:
		if Time.get_ticks_msec()>deadline:
			fail("snapshot")
			return
		await get_tree().process_frame
	var cassien = zone.get_node("CassienRitual")
	var nav = load("res://scripts/world/six_zone_reverie/expedition_navigation.gd")
	var initial: Dictionary = nav.resolve(zone)
	if not initial.ready or not initial.valid or initial.position!=cassien.global_position or initial.rows.size()!=5 or initial.rows[0].done:
		fail("initial boss guidance")
		return
	var brazier = zone.get_node("RuinsBraziers/Western")
	if not cassien.can_interact() or brazier.can_interact() or not cassien.cassien_visual.visible:
		fail("initial gates")
		return
	cassien.interact()
	var dialog = zone.get_node("UI/Dialogue")
	var dialogue_deadline := Time.get_ticks_msec()+6000
	while not dialog.visible:
		if Time.get_ticks_msec()>dialogue_deadline:
			fail("Cassien dialogue did not open; distance "+str(zone.checkpoint_player.global_position.distance_to(cassien.global_position)))
			return
		await get_tree().process_frame
	if not dialog.visible or dialog._dialogue_id!="cassien_meeting":
		fail("meeting dialogue")
		return
	dialog._show_node("oath")
	dialog._choose(dialog._node.choices[0])
	await get_tree().process_frame
	await get_tree().process_frame
	if not is_instance_valid(cassien.coop_panel) or zone.get_node("CombatRouter").active_combat!=null:
		fail("shared panel")
		return
	var panel = cassien.coop_panel.get_node("Center/Panel/Content")
	if panel.get_node("Health").max_value!=600 or panel.get_node_or_null("Portrait/Cassien")==null:
		fail("panel art or health")
		return
	print("PASS Cassien awakening, authored dialogue and shared combat panel")
	var role := OS.get_environment("QA_ROLE")
	await get_tree().create_timer(0.8 if role=="A" else 1.1).timeout
	deadline=Time.get_ticks_msec()+16000
	var warnings := {}
	var clips := {}
	var guard_confirmed := false
	var next_strike := 0
	while not cassien.coop_defeated:
		var guard: Button = panel.get_node("Guard")
		if not cassien.coop_warning.is_empty():
			warnings[str(cassien.coop_warning.get("name"))] = true
			if cassien.coop_guarded and str(cassien.coop_warning.get("targetId")) == sync.local_player_id:
				guard_confirmed = true
			if guard.visible and not guard.disabled:
				guard.pressed.emit()
		elif not panel.get_node("Attack").disabled and Time.get_ticks_msec() >= next_strike:
			panel.get_node("Attack").pressed.emit()
			next_strike = Time.get_ticks_msec()+680
		clips[str(cassien.coop_panel.art.animation)] = true
		await get_tree().create_timer(0.08).timeout
		if Time.get_ticks_msec()>deadline:
			fail("combat HP "+str(cassien.coop_hp))
			return
	if not warnings.has("Crimson Crescent") or not warnings.has("Crimson Requiem") or not clips.has("crimson_crescent") or not clips.has("crimson_requiem"):
		fail("special coverage "+str(warnings)+" "+str(clips))
		return
	print("PASS both shared warnings and special clips; local guard confirmed=",guard_confirmed)
	if not panel.get_node("Attack").disabled or not brazier.can_interact():
		fail("victory gates")
		return
	panel.get_node("Leave").pressed.emit()
	await get_tree().process_frame
	if not zone.checkpoint_player.input_enabled or zone.get_meta("coop_boss_panel_open",false):
		fail("battle exit")
		return
	var guide: Dictionary = nav.resolve(zone)
	if not guide.ready or not guide.valid or guide.position!=brazier.global_position or not guide.rows[0].done or not guide.rows[1].active:
		fail("ritual guidance "+str(guide))
		return
	print("PASS shared defeat, victory lock, western brazier unlocked and tracked")
	deadline=Time.get_ticks_msec()+5000
	while int(AuthGateway.online_wallet.get("gold",0))!=180 or int(AuthGateway.online_wallet.get("xp",0))!=140:
		if Time.get_ticks_msec()>deadline:
			fail("online reward")
			return
		await get_tree().process_frame
	if GameState.quest_domain.quest_state("cassien_resurrection")!=old_quest or GameState.inventory_domain.currency("gold")!=old_gold:
		fail("offline changed")
		return
	print("PASS individual rewards; offline state unchanged")
	MultiplayerGateway.disconnect_from_lobby()
	zone.queue_free()
	for i in range(3):
		await get_tree().process_frame
	AudioDirector.stop_all_audio_immediately()
	await get_tree().create_timer(0.35).timeout
	get_tree().quit(0)
