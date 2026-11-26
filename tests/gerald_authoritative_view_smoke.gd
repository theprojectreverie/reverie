extends Node
func _ready() -> void:
	call_deferred("_run")
func _run() -> void:
	var battle := (load("res://scenes/ui/combat_screen.tscn") as PackedScene).instantiate() as CombatScreen
	battle.group_id = "gerald_boss_encounter"
	add_child(battle)
	await get_tree().process_frame
	battle._turn_token += 1
	battle._resolved = false
	battle._animating = false
	var marker := Node.new()
	marker.name = "StoryOpeningWorldSync"
	add_child(marker)
	var session := battle._session_component
	session.bind(battle)
	remove_child(marker)
	marker.free()
	if not session.is_online_gerald():
		push_error("Authority was not latched")
		get_tree().quit(1)
		return
	var player := CombatFactory.build_from_character(CharacterInstance.from_dict({"char_id":"kael","uid":"qa-view","level":1}))
	var enemies := CombatFactory.enemy_units("gerald_boss_encounter", "village_solo")
	battle.engine = CombatEngine.new()
	battle.engine.setup([player], enemies)
	var rows: Array = []
	for unit in battle.engine.combatants:
		rows.append({"uid":unit.uid,"charId":unit.def_id,"team":unit.team,"hp":unit.max_hp*0.5,"maxHp":unit.max_hp,"atk":unit.atk,"defense":unit.defense,"energy":23.0,"shield":4.0,"skills":unit.skills.duplicate(),"ultimate":unit.ultimate,"cooldowns":{},"statuses":[],"phases":[],"defending":false})
	var view := {"status":"active","sequence":3,"round":2,"actorUid":player.uid,"units":rows,"events":[]}
	if not session._apply_spar_view(view) or not is_equal_approx(player.hp,player.max_hp*0.5) or player.energy!=23.0 or battle.engine.current_actor()!=player:
		push_error("Valid server view was not projected")
		get_tree().quit(1)
		return
	var bad := view.duplicate(true)
	bad.units[1].uid = player.uid
	bad.units[0].hp = 1.0
	if session._apply_spar_view(bad) or not is_equal_approx(player.hp,player.max_hp*0.5):
		push_error("Invalid server view mutated the battle")
		get_tree().quit(1)
		return
	var stale := view.duplicate(true)
	stale.sequence = 2
	stale.units[0].hp = 1.0
	if session._apply_spar_view(stale) or not is_equal_approx(player.hp,player.max_hp*0.5):
		push_error("Stale server view regressed the battle")
		get_tree().quit(1)
		return
	var reward := {"gold":42,"xp":10,"crystals":1,"items":{}}
	session._record_server_rewards({"rewards":reward})
	reward.gold = 999
	if session._server_rewards.gold != 42:
		push_error("Server rewards were not copied independently")
		get_tree().quit(1)
		return
	battle.queue_free()
	await get_tree().process_frame
	await AudioDirector.drain_for_shutdown()
	print("GERALD_AUTHORITATIVE_VIEW_SMOKE_PASS")
	get_tree().quit(0)
