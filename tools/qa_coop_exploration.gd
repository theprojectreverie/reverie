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
	var region := OS.get_environment("QA_REGION")
	var willow := region == "six_zone_willow_fields"
	var role := OS.get_environment("QA_ROLE")
	var quest := "willow_crossing" if willow else "elderwood_relics"
	var previous := GameState.quest_domain.quest_state(quest)
	var gold := GameState.inventory_domain.currency("gold")
	MultiplayerGateway.standalone_expedition_id = OS.get_environment("QA_LOBBY")
	MultiplayerGateway.standalone_expedition_region = region
	var data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://resources/data/six_zone_expeditions.json"))
	var zone = load(str(data[region]["scene"])).instantiate()
	add_child(zone)
	var sync = zone.get_node("CoopWorldSync")
	var nav = load("res://scripts/world/six_zone_reverie/expedition_navigation.gd")
	var pending: Dictionary = nav.resolve(zone)
	if pending.ready or pending.valid:
		fail("premature navigation")
		return
	var deadline := Time.get_ticks_msec()+12000
	while not sync._snapshot_ready or sync.remote_players.size()!=1:
		if Time.get_ticks_msec()>deadline:
			fail("snapshot")
			return
		await get_tree().process_frame
	var first = zone.get_node("WillowObjectives/RiverCrossing" if willow else "ElderwoodRelics/BrokenMemorial")
	var second = zone.get_node("WillowObjectives/EasternRuins" if willow else "ElderwoodRelics/WeatheredPillar")
	if not willow:
		if role=="A" and first.can_interact():
			first.interact()
		if role=="B":
			while sync.exploration_cleared.size()<1:
				if Time.get_ticks_msec()>deadline:
					fail("first relic")
					return
				await get_tree().process_frame
			if not second.can_interact():
				fail("second relic disabled")
				return
			second.interact()
	while sync.exploration_cleared.size()!=2:
		if Time.get_ticks_msec()>deadline:
			fail("completion "+str(sync.exploration_cleared))
			return
		await get_tree().process_frame
	await get_tree().create_timer(0.4).timeout
	if first.label.visible or second.label.visible or sync.next_exploration_objective()!="":
		fail("completed marker remains")
		return
	var guide: Dictionary = nav.resolve(zone)
	if not guide.ready or not guide.complete or not guide.portal or guide.rows.size()!=2 or not guide.rows.all(func(row):return row.done):
		fail("completed navigation "+str(guide))
		return
	var hud = zone.get_node("UI/HUD")
	hud.refresh_quest()
	if not hud._quest_label.visible or not zone.get_meta("chapter_navigation").complete:
		fail("shared HUD")
		return
	var router = zone.get_node("OverlayRouter")
	if not router.open_screen("quests"):
		fail("journal open")
		return
	await get_tree().process_frame
	var journal = router.active_overlay
	if journal._objectives.get_child_count()!=2 or not journal._cards.is_empty() or journal._detail_title.text!=guide.region:
		fail("shared journal rows")
		return
	journal.close_screen()
	await get_tree().process_frame
	if GameState.quest_domain.quest_state(quest)!=previous or GameState.inventory_domain.currency("gold")!=gold:
		fail("offline state changed")
		return
	print("PASS ",region," actual authored objectives completed, markers hidden, offline state untouched")
	MultiplayerGateway.disconnect_from_lobby()
	zone.queue_free()
	for i in range(3):
		await get_tree().process_frame
	AudioDirector.stop_all_audio_immediately()
	await get_tree().create_timer(0.35).timeout
	get_tree().quit(0)
