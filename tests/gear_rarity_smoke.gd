extends Node
var ok := true
func check(condition: bool, label: String) -> void:
	print("RARITY ",label,"=",condition)
	ok = ok and condition
func _ready() -> void:
	if OS.get_environment("REVERIE_E2E_DISABLE_LOCAL_SAVE") != "1":
		get_tree().quit(2)
		return
	var r := GameState.roster_domain
	var inv := GameState.inventory_domain
	var kael: CharacterInstance
	for i in r.roster:
		if i.char_id == "kael": kael = i
	if kael == null:
		get_tree().quit(1)
		return
	check(r.gear_cap("mossweave_vest")==5 and r.gear_cap("gladewood_bow")==6 and r.gear_cap("sunfire_blade")==7,"rarity_caps")
	check(not CraftingService.craft("gladewood_bow").ok,"missing_materials_rejected")
	inv.add_currency("gold",30000)
	inv.add_item("glade_sap",100)
	inv.add_item("moonpetal",20)
	inv.add_item("royal_seal",2)
	inv.add_item("gothic_shard",20)
	inv.add_item("dew_of_awakening",1)
	var gold := inv.currency("gold")
	var sap := inv.item_count("glade_sap")
	var petals := inv.item_count("moonpetal")
	var seals := inv.item_count("royal_seal")
	check(CraftingService.craft("gladewood_bow").ok,"craft_bow")
	check(inv.currency("gold")==gold-400 and inv.item_count("glade_sap")==sap-5 and inv.item_count("moonpetal")==petals-3 and inv.item_count("royal_seal")==seals-1,"bow_exact_cost")
	check(CraftingService.craft("awakening_dew").ok and inv.item_count("dew_of_awakening")==2,"dew_recipe")
	check(CraftingService.craft("sunfire_royal_forge").ok and inv.item_count("sunfire_blade")==1,"royal_forge_recipe")
	check(r.equip_item(kael.uid,"gladewood_bow"),"equip_bow")
	for i in range(5):
		check(r.enhance_gear(kael.uid,"weapon"),"bow_upgrade_%d"%(i+1))
	var old_shards := inv.item_count("gothic_shard")
	check(inv.remove_item("gothic_shard",old_shards),"remove_shards_fixture")
	gold=inv.currency("gold")
	sap=inv.item_count("glade_sap")
	check(not r.enhance_gear(kael.uid,"weapon") and inv.currency("gold")==gold and inv.item_count("glade_sap")==sap,"blocked_without_shards")
	inv.add_item("gothic_shard",old_shards)
	check(r.enhance_gear(kael.uid,"weapon") and r.gear_level(kael.uid,"weapon")==6 and inv.item_count("gothic_shard")==old_shards-1,"epic_six")
	check(not r.enhance_gear(kael.uid,"weapon"),"epic_cap")
	check(r.equip_item(kael.uid,"sunfire_blade"),"swap_legendary")
	check(r.best_stored_gear("gladewood_bow").get("level",0)==6,"stored_epic_six")
	for i in range(7):
		check(r.enhance_gear(kael.uid,"weapon"),"legendary_upgrade_%d"%(i+1))
	check(r.gear_level(kael.uid,"weapon")==7 and not r.enhance_gear(kael.uid,"weapon"),"legendary_cap")
	var base := CombatFactory.build_from_character(kael,1.0)
	check(r.unequip_item(kael.uid,"weapon"),"unequip_seven")
	var bare := CombatFactory.build_from_character(kael,1.0)
	check(is_equal_approx(base.atk-bare.atk,38.0*1.56),"legendary_stat_scaling")
	var uid := kael.uid
	var snapshot := JSON.parse_string(JSON.stringify(GameState._to_dict())) as Dictionary
	GameState._load_from_dict(snapshot)
	kael=r._find_instance(uid)
	check(r.best_stored_gear("gladewood_bow").get("level",0)==6 and r.best_stored_gear("sunfire_blade").get("level",0)==7,"high_level_save_roundtrip")
	check(r.equip_item(uid,"sunfire_blade") and r.gear_level(uid,"weapon")==7,"restore_legendary")
	check(GameState.reward_domain.build_battle_rewards("elder_hollow").items.get("hollow_heart",0)==1,"elder_heart_drop")
	check(GameState.reward_domain.build_battle_rewards("revienna_encounter").items.get("royal_seal",0)==1,"ravienna_seal_drop")
	check(ContentDB.get_quest("royal_gate_patrol").get("rewards",{}).get("items",{}).get("royal_seal",0)==1,"gate_seal_reward")
	var panel := load("res://scenes/items/ui/item_detail_panel.tscn").instantiate() as ItemDetailPanel
	add_child(panel)
	panel.show_item("sunfire_blade")
	panel._target_uid=uid
	panel.show_item("sunfire_blade")
	var capped := false
	for b in panel.find_children("*","Button",true,false):
		if b.text == "Fully enhanced" and b.disabled: capped=true
	check(capped,"inventory_cap_display")
	panel.queue_free()
	await get_tree().process_frame
	AudioDirector.stop_all_audio_immediately()
	await get_tree().create_timer(0.35).timeout
	print("RARITY_PASS=",ok)
	get_tree().quit(0 if ok else 1)
