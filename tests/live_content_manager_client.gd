extends Node

func _ready() -> void:
	call_deferred("_run")

func _run() -> void:
	AuthGateway.api_base_url = OS.get_environment("QA_API")
	assert(AuthGateway.login(OS.get_environment("QA_NAME"), OS.get_environment("QA_PASSWORD")) == OK)
	var auth = await AuthGateway.auth_result
	assert(auth[1])
	var screen := (load("res://scenes/ui/gacha_screen.tscn") as PackedScene).instantiate() as GachaScreen
	add_child(screen)
	var deadline := Time.get_ticks_msec()+10000
	while not screen._account_state_ready() and Time.get_ticks_msec()<deadline:
		await get_tree().process_frame
	assert(screen._account_state_ready())
	assert(screen.active_banner_catalog().has("live_manager_qa"))
	screen._select_banner("live_manager_qa")
	var hash := OS.get_environment("QA_ART")
	while not screen._banner_content._live_art_cache.has(hash) and Time.get_ticks_msec()<deadline:
		await get_tree().process_frame
	assert(screen._banner_content._live_art_cache.has(hash))
	assert(screen._banner_content._live_art_target.portrait_texture.get_size()==Vector2(192,192))
	assert(screen._summon_flow.online_state.liveEvents.size()==1)
	await screen._claim_live_event("event_manager_qa")
	assert(screen.summon_currency("crystals")==1300)
	assert(screen._summon_flow.online_state.liveEvents[0].claimed)
	var gold := screen.summon_currency("gold")
	assert(gold>=10)
	var stock := int(screen._summon_flow.online_state.inventory.get("moonpetal",0))
	var offer: Dictionary = screen._summon_flow.online_state.liveEvents[0].shop
	screen._confirm_live_event_purchase("event_manager_qa",offer,"Moonpetal")
	var dialog: ConfirmationDialog = null
	for child in screen.get_children():
		if child is ConfirmationDialog and child.title == "Event shop purchase": dialog=child
	assert(dialog != null)
	dialog.confirmed.emit()
	while screen._summon_busy and Time.get_ticks_msec()<deadline:
		await get_tree().process_frame
	assert(not screen._summon_busy)
	assert(screen.summon_currency("gold")==gold-10, "Gold before %d after %d" % [gold,screen.summon_currency("gold")])
	assert(int(screen._summon_flow.online_state.inventory.get("moonpetal",0))==stock+1)
	assert(screen._summon_flow.online_state.liveEvents[0].purchased)
	print("LIVE_CONTENT_CLIENT_PASS: verified downloaded portrait, event reward and confirmed shop purchase through Godot")
	screen.queue_free()
	AudioDirector.stop_all_audio_immediately()
	await get_tree().process_frame
	await get_tree().create_timer(0.2).timeout
	get_tree().quit(0)
