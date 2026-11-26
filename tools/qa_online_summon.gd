extends Node
func _ready():
	call_deferred("run")
func fail(reason: String):
	print("FAIL ",reason)
	get_tree().quit(1)
func run():
	AuthGateway.api_base_url=OS.get_environment("QA_API")
	if AuthGateway.login(OS.get_environment("QA_NAME"),OS.get_environment("QA_PASSWORD"))!=OK:
		fail("login"); return
	var auth=await AuthGateway.auth_result
	if not auth[1]:
		fail("auth"); return
	var bag: InventoryScreen = load("res://scenes/ui/inventory_screen.tscn").instantiate()
	add_child(bag)
	var deadline := Time.get_ticks_msec()+5000
	while AuthGateway.online_wallet.is_empty() and Time.get_ticks_msec()<deadline:
		await get_tree().process_frame
	if not bag._online_mode or AuthGateway.online_wallet.is_empty():
		fail("inventory online mode"); return
	if bag._online_inventory_panel.get_child_count()!=5:
		fail("inventory items "+str(bag._online_inventory_panel.get_child_count())); return
	var old_item: Node = bag._online_inventory_panel.get_child(0)
	bag._refresh_online_inventory()
	if bag._online_inventory_panel.get_child(0) != old_item:
		fail("unchanged bag rebuild"); return
	bag._online_layout.get_node("Filters/Search").text = "Gladewood"
	bag._refresh_online_inventory()
	if bag._online_inventory_panel.get_child_count()!=1:
		fail("inventory search"); return
	bag._set_inventory_mode(false)
	if not bag._online_mode or bag._local_layout != null or not bag._online_layout.visible or bag._inventory_mode.visible:
		fail("offline inventory must remain disabled"); return
	var menu: MainMenu=load("res://scenes/ui/main_menu.tscn").instantiate()
	add_child(menu)
	await get_tree().process_frame
	if menu.get_node("ReferenceInterface/CurrencyBar/PremiumCurrency").text != UIFactory.number(1200):
		fail("main menu wallet"); return
	menu.queue_free()
	bag.queue_free()
	await get_tree().process_frame
	print("PASS main menu wallet, online inventory, search and local isolation")
	var collection: CollectionScreen = load("res://scenes/ui/collection_screen.tscn").instantiate()
	add_child(collection)
	collection._open_online_collection()
	for i in range(100):
		if collection.has_node("OnlineCollectionOverlay/OnlineRosterDialog") and collection.get_node("OnlineCollectionOverlay/OnlineRosterDialog").visible: break
		await get_tree().create_timer(0.05).timeout
	var opened: GachaScreen = collection.get_node_or_null("OnlineCollectionOverlay")
	if opened == null or not opened.get_node("OnlineRosterDialog").visible or opened.summon_currency("crystals") != 1200:
		fail("party online shortcut"); return
	if opened.get_node("SummoningChamberAtmosphere").is_processing() or opened._main.get_child_count() != 0:
		fail("collection renders hidden summon banner"); return
	opened.get_node("OnlineRosterDialog").hide()
	collection.queue_free()
	await get_tree().process_frame
	print("PASS Party screen online collection shortcut")

	var scene: GachaScreen=load("res://scenes/ui/gacha_screen.tscn").instantiate()
	add_child(scene)
	await get_tree().process_frame
	var local_balance:=GameState.inventory_domain.currency("crystals")
	var local_roster_count:=GameState.roster.size()
	await scene._toggle_online(true)
	if not scene._online_mode or scene.summon_currency("crystals")!=1200:
		fail("online wallet"); return
	if not scene.summon_available(10,1200,"crystals"):
		fail("affordability"); return
	scene._show_online_roster()
	var local_before := JSON.stringify(GameState._to_dict())
	var online_before: Dictionary = scene._summon_flow.online_state.duplicate(true)
	await scene._show_progress_comparison()
	var preview: AcceptDialog = scene.get_node("OnlineRosterDialog/ProgressComparison")
	if not preview.visible:
		fail("comparison not visible"); return
	var report: String = preview.get_node("Content/Scroll/Report").text
	if not report.contains("CURRENCIES") or not report.contains("1,500") or not report.contains("1,200") or not report.contains("CHARACTERS") or not report.contains("UNEQUIPPED ITEMS"):
		fail("comparison content "+report); return
	if JSON.stringify(GameState._to_dict()) != local_before or scene._summon_flow.online_state != online_before:
		fail("comparison mutated progression"); return
	preview.hide()
	print("PASS read-only local/online comparison, separate balances and unchanged progression")
	for row in scene._summon_flow.online_state.get("roster", []):
		if str(row.char_id) == "kael":
			scene._online_character_details(row, ContentDB.get_character("kael"))
			break
	if scene.get_node("OnlineRosterDialog/BodyScroll/Collection/UpgradeRow/Ascend").disabled:
		fail("ascension button"); return
	await scene._upgrade_online_character("ascend")
	if int(scene._online_selected.get("ascension", 0)) != 1 or scene.summon_currency("gold") != 400:
		fail("ascension UI state"); return
	if scene.get_node("OnlineRosterDialog/BodyScroll/Collection/UpgradeRow/Awaken").disabled:
		fail("awakening button"); return
	await scene._upgrade_online_character("awaken")
	if int(scene._online_selected.get("awakening", 0)) != 1 or int(scene._online_selected.get("dupes", -1)) != 0:
		fail("awakening UI state"); return
	var skill_picker: OptionButton = scene.get_node("OnlineRosterDialog/BodyScroll/Collection/SkillRow/Skill")
	for i in range(skill_picker.item_count):
		if str(skill_picker.get_item_metadata(i)) == "ember_lance": skill_picker.select(i)
	scene._refresh_skill_controls()
	if scene.get_node("OnlineRosterDialog/BodyScroll/Collection/SkillRow/Upgrade").disabled:
		fail("skill upgrade button"); return
	await scene._upgrade_online_skill()
	if int(scene._online_selected.get("skill_levels", {}).get("ember_lance",1)) != 2 or scene.summon_currency("gold") != 300:
		fail("skill UI state"); return
	print("PASS online skill upgrade interface, persisted level, gold and materials")
	var gear: Node = scene.get_node("OnlineRosterDialog/BodyScroll/Collection/GearRow")
	if gear.get_node("Equip").disabled:
		fail("equip button"); return
	await scene._online_gear_action("equip")
	if str(scene._current_online_gear().get("item_id","")) != "gladewood_bow":
		fail("equipped state"); return
	if gear.get_node("Enhance").disabled:
		fail("enhance button"); return
	await scene._online_gear_action("enhance")
	if int(scene._current_online_gear().get("enhancement_level",0)) != 1 or scene.summon_currency("gold") != 120:
		fail("enhancement state"); return
	await scene._online_gear_action("unequip")
	if not scene._current_online_gear().is_empty():
		fail("unequip state"); return
	await scene._online_gear_action("equip")
	if int(scene._current_online_gear().get("enhancement_level",0)) != 1:
		fail("restored gear state"); return
	print("PASS equipment interface, enhancement, unequip and restoration")
	if gear.get_node("Reroll").disabled:
		fail("reroll button"); return
	await scene._online_gear_action("reroll")
	var rolled := scene._current_online_gear()
	if not ["atk","spd"].has(rolled.get("reroll_stat")) or scene.summon_currency("gold") != 0:
		fail("reroll state"); return
	await scene._online_gear_action("unequip")
	await scene._online_gear_action("equip")
	if scene._current_online_gear().get("reroll_stat") != rolled.get("reroll_stat") or scene._current_online_gear().get("reroll_value") != rolled.get("reroll_value"):
		fail("restored reroll"); return
	print("PASS reroll interface, costs and persistence")
	var original_party: Array = scene._summon_flow.online_state.get("party",[]).duplicate()
	if not original_party.has("kael") or original_party.size()!=3:
		fail("default party"); return
	await scene._change_online_party(true)
	if scene._summon_flow.online_state.get("party",[]).has("kael"):
		fail("party remove"); return
	await scene._change_online_party(true)
	if not scene._summon_flow.online_state.get("party",[]).has("kael"):
		fail("party add"); return
	await scene._change_online_party(false)
	print("PASS online party editor, persistence and confirmation")
	for row in scene._summon_flow.online_state.get("roster",[]):
		if str(row.char_id) == "kael":
			scene._online_character_details(row,ContentDB.get_character("kael"))
			row["xp"] = "9999"
			break
	var perf_grid: GridContainer = scene.get_node("OnlineRosterDialog/BodyScroll/Collection/Scroll/Grid")
	var perf_card: Node = perf_grid.get_child(0)
	AuthGateway.online_wallet_changed.emit()
	await get_tree().create_timer(1.1).timeout
	if scene._online_selected.get("char_id") != "kael" or str(scene._online_selected.get("xp","")) == "9999":
		fail("live collection refresh"); return
	for row in scene._summon_flow.online_state.get("roster",[]):
		if str(row.char_id) == "kael" and str(row.get("xp","")) == "9999":
			fail("stale XP"); return
	if perf_grid.get_child(0) != perf_card:
		fail("XP-only update rebuilt cards"); return
	print("PASS unchanged inventory and XP-only collection refresh preserve UI nodes")
	print("PASS live wallet-triggered collection refresh and selected character preservation")




	scene.get_node("OnlineRosterDialog").hide()
	print("PASS online ascension and awakening UI, wallet and materials")
	if OS.get_environment("QA_PROGRESSION_ONLY") == "1":
		if GameState.inventory_domain.currency("crystals") != local_balance or GameState.roster.size() != local_roster_count:
			fail("local save altered"); return
		scene.queue_free()
		await get_tree().process_frame
		await AudioDirector.drain_for_shutdown()
		get_tree().quit(0)
		return
	var result:=await scene._summon_flow.pull_online("crimson_covenant",10)
	if not result.get("ok",false):
		fail("pull "+str(result)); return
	if result.results.size()!=10 or scene.summon_currency("crystals")!=0:
		fail("results or wallet"); return
	if scene._summon_flow.online_state.get("roster",[]).size()<3:
		fail("online roster"); return
	if GameState.inventory_domain.currency("crystals")!=local_balance or GameState.roster.size()!=local_roster_count:
		fail("local save altered"); return
	if not scene._summon_flow.pending_online.is_empty():
		fail("pending after commit"); return
	var expected_count: int = scene._summon_flow.online_state.get("roster", []).size()
	scene._show_online_roster()
	var grid: GridContainer = scene.get_node("OnlineRosterDialog/BodyScroll/Collection/Scroll/Grid")
	if grid.get_child_count()!=expected_count:
		fail("online gallery count"); return
	scene._filter_online_roster("not_a_character")
	if grid.get_child_count()!=0:
		fail("online gallery search"); return
	scene._filter_online_roster("Kael")
	if grid.get_child_count()<1:
		fail("online gallery Kael"); return
	scene.get_node("OnlineRosterDialog").hide()
	await scene._toggle_online(false)
	if not scene._online_mode or scene.summon_currency("crystals")!=0 or GameState.inventory_domain.currency("crystals")!=local_balance:
		fail("account wallet isolation"); return
	print("PASS actual Godot online summon transport, wallet, collection, separate local state")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(scene._summon_flow._journal_path()))
	scene.queue_free()
	await get_tree().process_frame
	await AudioDirector.drain_for_shutdown()
	get_tree().quit(0)
