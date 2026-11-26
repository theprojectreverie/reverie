extends Node
const MOCK = preload("res://tests/story_combat_mock_session.gd")
const BATTLE_ID := "qa-gerald-recovery"
var failures: Array[String] = []

func _ready() -> void:
	call_deferred("_run")

func check(ok: bool, message: String) -> void:
	if not ok:
		failures.append(message)
		push_error(message)
	else:
		print("PASS " + message)

func view(seq: int, terminal: bool = false) -> Dictionary:
	var player := CombatFactory.build_from_character(CharacterInstance.from_dict({"char_id":"kael","uid":"account:kael","level":1}))
	var foes := CombatFactory.enemy_units("gerald_boss_encounter", "village_solo")
	var engine := CombatEngine.new()
	engine.setup([player], foes)
	var rows: Array = []
	for unit in engine.combatants:
		rows.append({"uid":unit.uid,"charId":unit.def_id,"team":unit.team,"hp":0.0 if terminal and unit.team==1 else unit.max_hp*(1.0-0.1*seq),"maxHp":unit.max_hp,"atk":unit.atk,"defense":unit.defense,"energy":float(seq*10),"shield":0.0,"skills":unit.skills.duplicate(),"ultimate":unit.ultimate,"cooldowns":{},"statuses":[],"phases":[],"defending":false})
	return {"status":"victory" if terminal else "active","sequence":seq,"round":1,"actorUid":"" if terminal else player.uid,"units":rows,"events":[]}

func response(seq: int, terminal: bool = false) -> Dictionary:
	return {"battleId":BATTLE_ID,"view":view(seq,terminal),"rewards":{"gold":42,"xp":10,"crystals":2,"items":{}} if terminal else null}

func _run() -> void:
	if OS.get_environment("REVERIE_E2E_DISABLE_LOCAL_SAVE") != "1" or AuthGateway.is_authenticated():
		get_tree().quit(2)
		return
	var marker := Node.new()
	marker.name = "StoryOpeningWorldSync"
	add_child(marker)
	var battle := (load("res://scenes/ui/combat_screen.tscn") as PackedScene).instantiate() as CombatScreen
	battle.group_id = "gerald_boss_encounter"
	var session = battle.get_node("Session")
	session.set_script(MOCK)
	session.responses.assign([response(0), {}, {}, response(1), {}, response(2,true)])
	add_child(battle)
	await get_tree().create_timer(0.5).timeout
	check(battle.engine != null and session.is_online_gerald(), "authoritative screen initialized")
	if battle.engine == null:
		get_tree().quit(1)
		return
	await session.defend()
	check(session._needs_story_recovery and session._spar_sequence == 0 and session.requests.size()==3, "lost action and resume leave recovery pending")
	await session.end_turn()
	check(not session._needs_story_recovery and session._spar_sequence==1 and session.requests.size()==4 and session.requests[3].operation=="resume", "next click only recovers committed state")
	check(battle.engine.current_actor().energy==10.0 and not battle._animating, "recovered actor and input restored")
	await session.defend()
	check(session.requests.size()==6 and session.requests[4].sequence==2 and session.requests[5].operation=="resume", "subsequent action uses next committed sequence")
	check(battle._resolved and battle._result_layer!=null and session._spar_verified and int(battle._pending_rewards.get("gold",0))==42, "lost victory response restores actual reward overlay")
	check(session.responses.is_empty(), "all expected requests consumed")
	battle.queue_free()
	await get_tree().process_frame
	var retreat := (load("res://scenes/ui/combat_screen.tscn") as PackedScene).instantiate() as CombatScreen
	retreat.group_id = "gerald_boss_encounter"
	var retreat_session = retreat.get_node("Session")
	retreat_session.set_script(MOCK)
	retreat_session.responses.assign([response(0), {}, {"status":"abandoned"}])
	add_child(retreat)
	await get_tree().create_timer(0.5).timeout
	await retreat._result_component.claim(false)
	check(is_instance_valid(retreat) and not retreat._claimed and retreat_session.requests.size()==2, "unconfirmed retreat keeps the screen open")
	await retreat._result_component.claim(false)
	await get_tree().process_frame
	check(not is_instance_valid(retreat), "confirmed retreat closes the battle")
	await AudioDirector.drain_for_shutdown()
	print("GERALD_RECOVERY_SMOKE " + ("PASS" if failures.is_empty() else "FAIL"))
	get_tree().quit(0 if failures.is_empty() else 1)
