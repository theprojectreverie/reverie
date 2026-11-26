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
		fail("login start")
		return
	var result: Array = await AuthGateway.auth_result
	if not bool(result[1]):
		fail("login rejected")
		return
	GameState.quest_domain.flags["tutorial_complete"] = true
	MultiplayerGateway.standalone_expedition_id = OS.get_environment("QA_LOBBY")
	MultiplayerGateway.standalone_expedition_region = "six_zone_royal_gate"
	var zone = load("res://scenes/world/six_zone_reverie/individual_zones/zone_02_royal_gate_standalone.tscn").instantiate()
	add_child(zone)
	var sync = zone.get_node("CoopWorldSync")
	var deadline := Time.get_ticks_msec()+10000
	while not sync._snapshot_ready or sync.remote_players.size()!=1:
		if Time.get_ticks_msec()>deadline:
			fail("snapshot")
			return
		await get_tree().process_frame
	var monster = zone.get_node_or_null("RoyalGatePatrol/Crownling01")
	if monster == null or monster.world_hp != 120.0 or not is_instance_valid(zone.get_node_or_null("RoyalGatePatrol/Crownling02")):
		fail("authored patrol missing")
		return
	print("PASS both authored Crownlings present; 120 HP")
	var local_gold := GameState.currency("gold")
	var local_quest := GameState.quest_domain.quest_state("royal_gate_patrol")
	var role := OS.get_environment("QA_ROLE")
	await get_tree().create_timer(1.0 if role=="A" else 1.3).timeout
	deadline=Time.get_ticks_msec()+10000
	while not monster.defeated:
		monster.receive_world_hit(25.0)
		await get_tree().create_timer(0.68).timeout
		if Time.get_ticks_msec()>deadline:
			fail("patrol defeat")
			return
	if sync.patrol_cleared.size()!=1 or monster.world_hp!=0.0:
		fail("shared progress")
		return
	var nav = load("res://scripts/world/six_zone_reverie/expedition_navigation.gd")
	var guide: Dictionary = nav.resolve(zone)
	if not guide.ready or guide.complete or not guide.valid or guide.position.distance_to(zone.get_node("RoyalGatePatrol/Crownling02").global_position)>1.0 or not guide.rows[0].done or guide.rows[1].done:
		fail("shared patrol navigation "+str(guide))
		return
	print("PASS shared defeat, patrol progress 1/2, next living Crownling navigation")
	deadline=Time.get_ticks_msec()+5000
	while int(AuthGateway.online_wallet.get("gold",0))!=25 or int(AuthGateway.online_inventory.get("moonpetal",0))!=1:
		if Time.get_ticks_msec()>deadline:
			fail("wallet")
			return
		await get_tree().process_frame
	if GameState.currency("gold") != local_gold or GameState.quest_domain.quest_state("royal_gate_patrol") != local_quest:
		fail("offline progress changed")
		return
	print("PASS online rewards, offline quest and currency isolated")
	MultiplayerGateway.disconnect_from_lobby()
	zone.queue_free()
	for i in range(3):
		await get_tree().process_frame
	AudioDirector.stop_all_audio_immediately()
	await get_tree().create_timer(0.35).timeout
	get_tree().quit(0)
