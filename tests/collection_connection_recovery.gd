extends Node

func _ready() -> void:
	call_deferred("_run")

func _run() -> void:
	AuthGateway.api_base_url = OS.get_environment("QA_API")
	assert(AuthGateway.login(OS.get_environment("QA_NAME"),OS.get_environment("QA_PASSWORD")) == OK)
	var auth = await AuthGateway.auth_result
	assert(auth[1])
	var gacha := (load("res://scenes/ui/gacha_screen.tscn") as PackedScene).instantiate() as GachaScreen
	gacha.collection_only = true
	add_child(gacha)
	var deadline := Time.get_ticks_msec()+8000
	while not gacha._collection_visible() and Time.get_ticks_msec()<deadline:
		await get_tree().process_frame
	assert(gacha._collection_visible())
	var flow := gacha._summon_flow
	assert(flow.online_state_fresh)
	var owner := str(AuthGateway.current_player().get("id"))
	var snapshot := flow.online_state.duplicate(true)
	var grid: GridContainer = gacha._collection_body().get_node("Collection/Scroll/Grid")
	var count := grid.get_child_count()
	assert(count > 0)
	gacha._select_current_online_character("kael")
	assert(gacha._online_selected.get("char_id") == "kael")
	var original_api := AuthGateway.api_base_url
	AuthGateway.api_base_url = "http://127.0.0.1:1"
	await gacha._refresh_live_collection()
	assert(not flow.online_state_fresh and flow.online_state == snapshot)
	assert(gacha._collection_visible() and grid.get_child_count() == count)
	assert(gacha._online_selected.get("char_id") == "kael")
	assert(gacha._collection_retry.visible and not gacha._account_state_ready())
	assert(gacha._collection_body().get_node("Collection/UpgradeRow/Train").disabled)
	assert(gacha._collection_body().get_node("Collection/UpgradeRow/Ascend").disabled)
	assert(gacha._collection_body().get_node("Collection/SkillRow/Upgrade").disabled)
	assert(gacha._collection_body().get_node("Collection/PartyRow/SaveParty").disabled)
	assert(not gacha.summon_available(1,1,"crystals"))
	AuthGateway.api_base_url = original_api
	await gacha._retry_account_state()
	assert(flow.online_state_fresh and gacha._account_state_ready())
	assert(gacha._online_selected.get("char_id") == "kael" and not gacha._collection_retry.visible)
	print("RECOVERY_DIAG level=",gacha._online_selected.get("level")," gold=",gacha.summon_currency("gold")," busy=",gacha._upgrade_busy," ready=",gacha._account_state_ready()," button=",gacha._collection_body().get_node("Collection/UpgradeRow/Train").text)
	assert(not gacha._collection_body().get_node("Collection/UpgradeRow/Ascend").disabled)
	await gacha._ascend_selected()
	assert(int(gacha._online_selected.get("level")) == 21 and int(gacha._online_selected.get("ascension")) == 1)
	assert(gacha._collection_visible())
	assert(not flow._apply_online_snapshot({"code":200,"playerId":"different-account","roster":[],"party":[],"currencies":{}},owner))
	assert(flow.online_state.is_empty() and not flow.online_state_fresh)
	print("COLLECTION_RECOVERY_PASS: actual login, disconnected HTTP, retained read-only selection, no spending, retry, ascension, foreign snapshot rejected")
	get_tree().quit(0)
