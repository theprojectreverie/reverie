extends Node
var ok := true
func check(value: bool, name: String) -> void:
	print("PROGRESSION ",name,"=",value)
	ok = ok and value
func _ready() -> void:
	var r := GameState.roster_domain
	var inv := GameState.inventory_domain
	var kael: CharacterInstance
	for instance in r.roster:
		if instance.char_id == "kael": kael = instance
	if kael == null:
		get_tree().quit(1)
		return
	for slot in CharacterInstance.SLOTS:
		r.unequip_item(kael.uid, slot)
	kael.awakening = 0
	kael.dupes = 0
	r.add_character("kael")
	check(kael.dupes == 1 and kael.awakening == 0,"first_duplicate")
	r.add_character("kael")
	check(kael.dupes == 0 and kael.awakening == 1 and not r.awaken(kael.uid),"no_double_awakening")
	inv.add_currency("gold", 5000)
	inv.add_item("glade_sap", 20)
	inv.add_item("moonpetal", 10)
	inv.add_item("gothic_shard", 10)
	inv.add_item("dew_of_awakening", 3)
	var before_gold := inv.currency("gold")
	var before_sap := inv.item_count("glade_sap")
	var before_charm := inv.item_count("wayfarer_charm")
	check(CraftingService.craft("wayfarer_charm").ok,"craft_charm")
	check(inv.currency("gold") == before_gold - 150 and inv.item_count("glade_sap") == before_sap - 2 and inv.item_count("wayfarer_charm") == before_charm + 1,"craft_cost")
	var baseline := CombatFactory.build_from_character(kael,1.0)
	check(r.equip_item(kael.uid,"wayfarer_charm"),"equip_charm")
	var equipped := CombatFactory.build_from_character(kael,1.0)
	check(is_equal_approx(equipped.crit_chance-baseline.crit_chance,0.04),"equipment_crit")
	check(r.enhance_gear(kael.uid,"accessory"),"enhance")
	var enhanced := CombatFactory.build_from_character(kael,1.0)
	check(is_equal_approx(enhanced.crit_chance-baseline.crit_chance,0.0432),"enhancement_stats")
	var roll := r.reroll_gear(kael.uid,"accessory")
	check(roll.ok,"reroll")
	if roll.stat != "crit": roll = r.reroll_gear(kael.uid,"accessory")
	check(roll.ok and roll.stat == "crit" and is_equal_approx(float(roll.value),0.004),"crit_reroll_fraction")
	var rerolled := CombatFactory.build_from_character(kael,1.0)
	check(is_equal_approx(rerolled.crit_chance-enhanced.crit_chance,0.004),"reroll_combat_stats")
	inv.add_item("wayfarer_charm",1)
	check(not r.equip_item(kael.uid,"wayfarer_charm") and r.gear_level(kael.uid,"accessory")==1,"same_item_no_reset")
	check(r.unequip_item(kael.uid,"accessory"),"unequip")
	var naked := CombatFactory.build_from_character(kael,1.0)
	check(is_equal_approx(naked.crit_chance,baseline.crit_chance) and not r.gear_rerolls.has(kael.uid+"|accessory"),"no_ghost_reroll")
	var stored := r.best_stored_gear("wayfarer_charm")
	check(int(stored.get("level",0)) == 1 and str(stored.get("reroll",{}).get("stat","")) == "crit","stored_copy_preserved")
	var gerald: CharacterInstance
	for instance in r.roster:
		if instance.char_id == "gerald": gerald = instance
	var count_before := inv.item_count("wayfarer_charm")
	check(r.equip_item(gerald.uid,"wayfarer_charm"),"equip_upgraded_on_other_character")
	check(r.gear_level(gerald.uid,"accessory")==1 and r.gear_rerolls.get(gerald.uid+"|accessory",{}).get("stat","")=="crit","upgrades_follow_copy")
	check(inv.item_count("wayfarer_charm")==count_before-1 and r.stored_copies("wayfarer_charm").is_empty(),"no_duplicate_stored_copy")
	check(r.equip_item(kael.uid,"wayfarer_charm") and r.gear_level(kael.uid,"accessory")==0,"other_copy_stays_unenhanced")
	r.unequip_item(gerald.uid,"accessory")
	r.unequip_item(kael.uid,"accessory")
	var normal_count := inv.item_count("wayfarer_charm")-1
	check(inv.remove_item("wayfarer_charm",normal_count),"remove_plain_copies")
	check(not inv.remove_item("wayfarer_charm",1),"protect_enhanced_copy")
	var uid := kael.uid
	var snapshot := JSON.parse_string(JSON.stringify(GameState._to_dict())) as Dictionary
	GameState._load_from_dict(snapshot)
	kael = r._find_instance(uid)
	check(r.best_stored_gear("wayfarer_charm").get("level",0)==1,"stored_gear_save_roundtrip")
	check(r.equip_item(kael.uid,"wayfarer_charm") and r.gear_level(kael.uid,"accessory")==1 and r.gear_rerolls.has(kael.uid+"|accessory"),"restored_copy_equips")
	check(r.unequip_item(kael.uid,"accessory"),"final_unequip")

	kael.level = kael.level_cap()
	var asc_gold := inv.currency("gold")
	var asc_dew := inv.item_count("dew_of_awakening")
	check(r.ascend(kael.uid),"ascend")
	check(kael.ascension==1 and kael.level==21 and inv.currency("gold")==asc_gold-800 and inv.item_count("dew_of_awakening")==asc_dew-1,"ascension_cost_cap")
	for i in range(1,7):
		check(GameState.reward_domain.build_battle_rewards("rose_slime_garden_%d"%i).items.get("glade_sap",0)==1,"slime_loot_%d"%i)
	for i in range(1,4):
		check(GameState.reward_domain.build_battle_rewards("crownling_garden_%d"%i).items.get("moonpetal",0)==1,"crownling_loot_%d"%i)
	check(not ItemInteraction.drop_item("glade_sap",0).ok,"reject_zero_drop")
	check(not ItemInteraction.sell("glade_sap",-1).ok,"reject_negative_sell")
	var collection := load("res://scenes/ui/collection_screen.tscn") as PackedScene
	if collection != null:
		var screen := collection.instantiate()
		add_child(screen)
		await get_tree().process_frame
		var free_xp := false
		for button in screen.find_children("*","Button",true,false):
			if button.text == "Gain 100 XP": free_xp = true
		check(not free_xp,"no_free_xp_button")
		screen.queue_free()
		await get_tree().process_frame
	else:
		check(false,"collection_scene")
	AudioDirector.stop_all_audio_immediately()
	await get_tree().create_timer(0.35).timeout
	print("PROGRESSION_PASS=",ok)
	get_tree().quit(0 if ok else 1)
