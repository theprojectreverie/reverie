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
	var flow := screen._summon_flow
	var banner_id := "live_qa_client"
	assert(not screen.active_banner_catalog().has(banner_id))
	var manifest_path := OS.get_environment("QA_LIVE_MANIFEST")
	assert(not manifest_path.is_empty())
	var row: Dictionary = JSON.parse_string(OS.get_environment("QA_LIVE_ENTRY"))
	assert(row.id == banner_id)
	var file := FileAccess.open(manifest_path, FileAccess.WRITE)
	assert(file != null)
	file.store_string(JSON.stringify({"schema":1,"banners":[row]}))
	file.close()
	await screen._refresh_live_collection()
	assert(screen.active_banner_catalog().has(banner_id))
	assert(screen._tabs.get_child_count() == ContentDB.banners.size()+2)
	screen._select_banner(banner_id)
	assert(screen._featured_id == "cassien_legendary")
	assert(screen.summon_available(1,120,"crystals"))
	assert(not screen.summon_available(1,120,"paid_moonstones"))
	var result := await flow.pull_online(banner_id,1,"crystals")
	assert(result.get("ok") == true and int(result.get("spent"))==120)
	assert(screen.summon_currency("crystals")==1080)
	file = FileAccess.open(manifest_path, FileAccess.WRITE)
	assert(file != null)
	file.store_string(JSON.stringify({"schema":1,"banners":[]}))
	file.close()
	await screen._refresh_live_collection()
	assert(not screen.active_banner_catalog().has(banner_id))
	assert(screen._selected_banner != banner_id)
	assert(screen._tabs.get_child_count()==ContentDB.banners.size()+1)
	print("LIVE_BANNER_CLIENT_PASS: same running client discovered, displayed, summoned and removed scheduled banner")
	screen.queue_free()
	AudioDirector.stop_all_audio_immediately()
	await get_tree().process_frame
	await get_tree().create_timer(0.2).timeout
	get_tree().quit(0)
