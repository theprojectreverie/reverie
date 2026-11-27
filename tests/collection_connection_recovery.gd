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
	var hero = gacha._collection_body().get_node("Collection/UpgradeHero")
	assert(hero.visible and hero.get_node("Layout/Portrait").portrait_texture != null)
	assert(hero.get_node("Layout/Level").text == "Level 20 / 20")
	assert(not gacha._collection_body().get_node("Collection/ConnectionRow/Retry").visible)
	var original_api := AuthGateway.api_base_url
	AuthGateway.api_base_url = "http://127.0.0.1:1"
	await gacha._refresh_live_collection()
	assert(not flow.online_state_fresh and flow.online_state == snapshot)
	assert(gacha._collection_visible() and grid.get_child_count() == count)
	assert(gacha._online_selected.get("char_id") == "kael")
	assert(gacha._collection_retry.visible and not gacha._account_state_ready())
	assert(gacha._collection_body().get_node("Collection/ConnectionRow/Retry").visible and hero.visible)
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
	gacha._select_current_online_character("ravienna")
	assert(int(gacha._online_selected.get("level",0)) == 1)
	for i in range(12):
		assert(not gacha._collection_body().get_node("Collection/UpgradeRow/Train").disabled)
		await gacha._train_selected()
		assert(int(gacha._online_selected.get("level",0)) == i + 2)
		assert(flow.online_state_fresh and gacha._account_state_ready())
	print("RAVIENNA TWELVE CONSECUTIVE LEVEL UPS PASS")
	var bulk: Button = gacha._collection_body().get_node("Collection/UpgradeRow/TrainMax")
	assert(not bulk.disabled and bulk.text.contains("Lv 20"))
	var before_gold := gacha.summon_currency("gold")
	var plan := gacha._training_plan(gacha._online_selected)
	assert(int(plan.target)==20)
	await gacha._train_max_selected()
	assert(int(gacha._online_selected.level)==20 and bulk.disabled)
	assert(before_gold-gacha.summon_currency("gold")==int(plan.cost))
	var retry := await flow._online_call("/train",{"characterId":"ravienna","expectedLevel":13,"expectedXp":0,"targetLevel":20})
	assert(int(retry.get("code"))==409)
	assert(flow.online_state_fresh and gacha._account_state_ready())
	print("BULK LEVEL 13 TO 20 PASS; STALE RETRY REJECTED")
	gacha._select_current_online_character("ravienna_mythic")
	var exchange: Button = gacha._collection_body().get_node("Collection/UpgradeRow/ExchangeCopies")
	assert(exchange.visible and not exchange.disabled and exchange.text.contains("10000"))
	var gold_before := gacha.summon_currency("gold")
	gacha._exchange_extra_copies()
	await get_tree().process_frame
	var dialog: ConfirmationDialog
	for child in gacha.get_children():
		if child is ConfirmationDialog and child.title=="Exchange surplus copies":dialog=child
	assert(dialog!=null and dialog.visible)
	var quantity: SpinBox
	for child in dialog.get_children():
		if child is VBoxContainer:
			for control in child.get_children():
				if control is SpinBox:quantity=control
	assert(quantity!=null and int(quantity.value)==2)
	quantity.value=1
	dialog.confirmed.emit()
	for i in range(600):
		if not gacha._upgrade_busy:break
		await get_tree().process_frame
	assert(not gacha._upgrade_busy and exchange.visible)
	assert(gacha.summon_currency("gold")==gold_before+5000)
	assert(exchange.text.contains("5000"))
	gacha._exchange_extra_copies()
	await get_tree().process_frame
	dialog=null
	for child in gacha.get_children():
		if child is ConfirmationDialog and child.title=="Exchange surplus copies":dialog=child
	assert(dialog!=null and dialog.visible)
	dialog.confirmed.emit()
	for i in range(600):
		if not gacha._upgrade_busy:break
		await get_tree().process_frame
	assert(not gacha._upgrade_busy and not exchange.visible)
	assert(gacha.summon_currency("gold")==gold_before+10000)
	assert(int(gacha._online_selected.awakening)==3 and int(gacha._online_selected.dupes)==0 and int(gacha._online_selected.ascension)==3 and int(gacha._online_selected.level)==80)
	print("SURPLUS COPY UI CONFIRMATION PASS")
	assert(not flow._apply_online_snapshot({"code":200,"playerId":"different-account","roster":[],"party":[],"currencies":{}},owner))
	assert(flow.online_state.is_empty() and not flow.online_state_fresh)
	print("COLLECTION_RECOVERY_PASS: actual login, disconnected HTTP, retained read-only selection, no spending, retry, ascension, foreign snapshot rejected")
	get_tree().quit(0)
