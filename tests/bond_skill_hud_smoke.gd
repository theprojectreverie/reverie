extends Node
func _ready() -> void:
	call_deferred("run")
func make_unit(id:String, asc:int=3) -> Combatant:
	var u := Combatant.new()
	u.uid=id
	u.def_id=id
	u.display_name=id
	u.ascension=asc
	u.hp=1000
	u.max_hp=1000
	u.speed=100
	u.atk=100
	u.defense=100
	return u
func run() -> void:
	var battle := (load("res://scenes/ui/combat_screen.tscn") as PackedScene).instantiate() as CombatScreen
	battle.group_id="elder_hollow"
	add_child(battle)
	for i in range(100): await get_tree().process_frame
	battle._turn_token+=1
	battle._resolved=false
	battle._animating=false
	battle._speed=4
	battle._auto=false
	var g:=make_unit("gerald_mythic")
	var l:=make_unit("lilith_mythic")
	var c:=make_unit("cassien_mythic")
	var r:=make_unit("ravienna_mythic")
	var e:=make_unit("enemy",0)
	var engine:=CombatEngine.new()
	engine.setup([g,l,c,r],[e])
	engine.start()
	battle.engine=engine
	engine.current_actor_index=g.combat_index
	battle._hud_component._active_action_category="ultimate"
	battle._hud_component.refresh_skills()
	var bond:Button
	for node in battle._skills_box.get_children():
		if node is Button and node.text.begins_with("Beyond Death"):bond=node
	if bond==null or not bond.disabled:
		push_error("missing or enabled uncharged bond card");get_tree().quit(1);return
	engine.bond_gauges["beyond_death"]=100
	battle._hud_component.refresh_skills()
	bond=null
	for node in battle._skills_box.get_children():
		if node is Button and node.text.begins_with("Beyond Death"):bond=node
	if bond==null or bond.disabled:
		push_error("charged bond card disabled");get_tree().quit(1);return
	print("BOND HUD: charge and readiness PASS")
	for id in ["beyond_death","eternal_eclipse"]:
		await battle._event_presentation_component.process_events([{"type":"bond","bond_id":id,"skill_name":CombatEngine.BOND_NAMES[id]}])
		await get_tree().process_frame
		for child in battle.get_children():
			if child is CanvasLayer and child.layer==50:
				push_error("bond overlay leaked");get_tree().quit(1);return
		print("BATTLE CINEMATIC PLAYBACK PASS: ",id)
	battle.queue_free()
	await get_tree().process_frame
	var pvp := (load("res://scenes/online/pvp_screen.tscn") as PackedScene).instantiate()
	add_child(pvp)
	PvpGateway.stop_polling()
	pvp._queue_bond_cinematics({"matchId":"bond-smoke"},[{"sequence":1,"event":{"type":"bond","bond_id":"eternal_eclipse"}}])
	await get_tree().process_frame
	if not pvp._bond_playing:
		push_error("PvP cinematic not running");get_tree().quit(1);return
	while pvp._bond_playing:await get_tree().process_frame
	pvp._queue_bond_cinematics({"matchId":"bond-smoke"},[{"sequence":1,"event":{"type":"bond","bond_id":"eternal_eclipse"}}])
	if pvp._bond_playing:
		push_error("duplicate PvP cinematic");get_tree().quit(1);return
	print("PVP CINEMATIC PLAYBACK AND DEDUP PASS")
	pvp.queue_free()
	await get_tree().process_frame
	get_tree().quit(0)

