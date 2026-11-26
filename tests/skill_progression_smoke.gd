extends Node
var ok := true
func check(value: bool, label: String) -> void:
	print("SKILL_TEST ",label,"=",value)
	ok = ok and value
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
	var id := "ember_lance"
	check(kael.skill_level(id)==1,"legacy_default")
	check(not r.upgrade_skill(kael.uid,id),"level_gate")
	kael.level = 20
	inv.add_currency("gold",5000)
	inv.add_item("moonpetal",30)
	var gold := inv.currency("gold")
	var petals := inv.item_count("moonpetal")
	check(not r.upgrade_skill(kael.uid,"corruption_bolt"),"unknown_skill_rejected")
	check(r.upgrade_skill(kael.uid,id),"upgrade")
	check(kael.skill_level(id)==2 and inv.currency("gold")==gold-100 and inv.item_count("moonpetal")==petals-1,"exact_cost")
	check(kael.skill_level("rally_cry")==1,"independent_skill")
	var baseline := CombatFactory.build_from_character(kael,1.0)
	baseline.skill_levels[id]=1
	var upgraded := CombatFactory.build_from_character(kael,1.0)
	check(is_equal_approx(upgraded.skill_power_multiplier(id),1.05),"factory_carries_level")
	var skill := ContentDB.get_skill(id)
	var enemy_a := Combatant.new()
	var enemy_b := Combatant.new()
	for e in [enemy_a,enemy_b]:
		e.max_hp=10000
		e.hp=10000
		e.team=1
	var engine_a := CombatEngine.new()
	var engine_b := CombatEngine.new()
	engine_a.rng.seed=123
	engine_b.rng.seed=123
	var a := engine_a._deal_damage(baseline,skill,enemy_a)
	var b := engine_b._deal_damage(upgraded,skill,enemy_b)
	check(int(b[0].amount)>int(a[0].amount),"damage_increases")
	check(is_equal_approx(skill.power,96.0),"shared_definition_unchanged")
	for x in range(3):
		check(r.upgrade_skill(kael.uid,id),"upgrade_step_%d"%x)
	check(kael.skill_level(id)==5 and not r.upgrade_skill(kael.uid,id),"skill_cap")
	check(r.upgrade_skill(kael.uid,"rally_cry"),"buff_upgrade")
	var actor := CombatFactory.build_from_character(kael,1.0)
	var ally := Combatant.new()
	ally.max_hp=1000
	ally.hp=100
	var engine := CombatEngine.new()
	engine.rng.seed=5
	engine._apply_skill(actor,ContentDB.get_skill("rally_cry"),ally)
	check(is_equal_approx(ally.status_total("atk_up"),0.231),"buff_potency")
	actor.skill_levels["dawn_mend"]=2
	engine._apply_skill(actor,ContentDB.get_skill("dawn_mend"),ally)
	check(is_equal_approx(ally.hp,499.0),"heal_increases")
	actor.skill_levels["stone_bulwark"]=2
	engine._apply_skill(actor,ContentDB.get_skill("stone_bulwark"),ally)
	check(is_equal_approx(ally.shield,252.0),"shield_increases")
	var uid := kael.uid
	var snapshot := JSON.parse_string(JSON.stringify(GameState._to_dict())) as Dictionary
	GameState._load_from_dict(snapshot)
	kael=r._find_instance(uid)
	check(kael.skill_level(id)==5 and kael.skill_level("rally_cry")==2,"save_roundtrip")
	var screen := load("res://scenes/ui/collection_screen.tscn").instantiate() as CollectionScreen
	add_child(screen)
	await get_tree().process_frame
	screen._select(uid)
	await get_tree().process_frame
	var found := false
	for button in screen.find_children("*","Button",true,false):
		if button.text.begins_with("Upgrade to Lv 3") and not button.disabled:
			found = true
			button.pressed.emit()
			break
	await get_tree().process_frame
	check(found and kael.skill_level("rally_cry")==3,"collection_button")
	screen.queue_free()
	await get_tree().process_frame
	AudioDirector.stop_all_audio_immediately()
	await get_tree().create_timer(0.35).timeout
	print("SKILL_TEST_PASS=",ok)
	get_tree().quit(0 if ok else 1)
