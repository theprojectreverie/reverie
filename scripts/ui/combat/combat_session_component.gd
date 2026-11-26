class_name CombatSessionComponent
extends Node
## Owns battle initialization and party/enemy staging for one CombatScreen.



var screen: CombatScreen
var _spar_http: HTTPRequest
var _spar_id := ""
var _spar_owner := ""
var _spar_sequence := 0
var _spar_actor := ""
var _spar_busy := false
var _spar_verified := false
var _spar_unlock_notice := false

var _server_rewards: Dictionary = {}
var _needs_story_recovery := false

var _gerald_authoritative := false
var _garden_authoritative := false

func is_online_garden() -> bool:
	return _garden_authoritative

func is_online_gerald() -> bool:
	return _gerald_authoritative

func is_authoritative_story() -> bool:
	return is_online_spar() or is_online_gerald() or is_online_garden()

func is_online_spar() -> bool:
	return screen != null and screen.group_id == "tutorial_fairy_spar"

func bind(owner_screen: CombatScreen) -> void:
	screen = owner_screen
	var world := screen.get_tree().current_scene
	# Latch authority for the lifetime of the battle. Scene teardown must never
	# turn an online encounter into a local reward or local damage path.
	_gerald_authoritative = screen.group_id == "gerald_boss_encounter" and world != null and world.has_node("StoryOpeningWorldSync")
	_garden_authoritative = world != null and world.has_node("StoryGardenCombatSync") and screen.group_id in ["rose_slime_garden_1", "rose_slime_garden_2", "rose_slime_garden_3", "rose_slime_garden_4", "rose_slime_garden_5", "rose_slime_garden_6", "crownling_garden_1", "crownling_garden_2", "crownling_garden_3", "royal_gate_patrol_1", "royal_gate_patrol_2"]

func start_battle() -> void:
	if screen == null or not is_instance_valid(screen):
		return
	screen._resolved = false
	screen._targeting_component.reset()
	screen._turn_token += 1
	if screen._feedback != null:
		screen._feedback.clear_log()

	var group: Dictionary = ContentDB.get_enemy_group(screen.group_id)
	if group.is_empty():
		push_error("[CombatScreen] Unknown enemy group: " + screen.group_id)
		screen._claim(false)
		return
	screen._title_label.text = str(group.get("name", screen.group_id))
	screen._round_label.text = "Round 1"
	if is_authoritative_story():
		if is_online_garden() and OS.get_environment("REVERIE_GARDENS_STORY_PILOT") != "1":
			screen._claim(false)
			return
		if is_online_gerald() and OS.get_environment("REVERIE_GERALD_STORY_PILOT") != "1":
			EventBus.toast_requested.emit("Online Gerald combat is unavailable.")
			screen._claim(false)
			return
		await _start_online_spar()
		return

	if AuthGateway.is_authenticated():
		var ready := await AuthGateway.refresh_account_roster()
		if not is_instance_valid(screen) or not screen.is_inside_tree():
			return
		if not ready:
			EventBus.toast_requested.emit("Reconnect to load your account party.")
			screen._claim(false)
			return
	var player_units := CombatFactory.player_units()
	if screen.group_id == "tutorial_fairy_spar":
		player_units = player_units.filter(func(unit): return unit.def_id == "kael")
	var profile := ""
	var world := screen.get_tree().current_scene
	if screen.group_id == "gerald_boss_encounter" and world != null and world.name == &"StandaloneVillage":
		profile = "village_solo"
		player_units = player_units.filter(func(unit): return unit.def_id == "kael")
	if screen.group_id == "revienna_encounter" and world != null and world.name == &"StandaloneZone06":
		profile = "story_tower"
	var enemy_units := CombatFactory.enemy_units(screen.group_id, profile)
	if player_units.is_empty() or enemy_units.is_empty():
		push_error("[CombatScreen] Battle has no units.")
		screen._claim(false)
		return


	screen.engine = CombatEngine.new()
	screen.engine.setup(player_units, enemy_units, randi())
	for unit in enemy_units:
		if unit.is_boss:
			screen._title_label.text = "Boss encounter"
			if screen._boss_name_label != null:
				screen._boss_name_label.text = unit.display_name
			if screen._boss_hp_bar != null:
				screen._boss_hp_bar.max_value = unit.max_hp
				screen._boss_hp_bar.value = unit.hp
			if screen._boss_bar_container != null:
				screen._boss_bar_container.visible = true
			screen._show_boss_intro(unit.display_name)

	var party_units: Array = []
	var enemy_stage_units: Array = []
	for unit in screen.engine.combatants:
		if unit.team == CombatEngine.PLAYER_TEAM:
			party_units.append(unit)
		else:
			enemy_stage_units.append(unit)
	if screen._battlefield != null:
		screen._battlefield.setup(party_units, enemy_stage_units)
	screen._build_roster(party_units)
	screen._log("[color=#e8c27a]Battle begins.[/color]")
	await screen._process_events(screen.engine.start())


func _begin_action() -> bool:
	if screen == null or not is_instance_valid(screen) or not screen.is_inside_tree():
		return false
	if screen.engine == null or screen._resolved or screen._animating:
		return false
	screen._cancel_targeting()
	screen._set_action_locked(true)
	return true


func _finish_action() -> void:
	if screen == null or not is_instance_valid(screen) or not screen.is_inside_tree():
		return
	screen._set_action_locked(false)


func defend() -> void:
	if is_authoritative_story():
		await _send_spar_action({"kind":"defend","actorUid":_spar_actor})
		return
	if not _begin_action():
		return
	var events := screen.engine.defend(screen.engine.current_actor_index)
	if events.is_empty():
		_finish_action()
		return
	await screen._process_events(events)
	if not is_instance_valid(screen) or not screen.is_inside_tree():
		return
	await screen.get_tree().process_frame
	_finish_action()


func end_turn() -> void:
	if is_authoritative_story():
		await _send_spar_action({"kind":"end_turn","actorUid":_spar_actor})
		return
	if not _begin_action():
		return
	var events := screen.engine.end_turn(screen.engine.current_actor_index)
	if events.is_empty():
		_finish_action()
		return
	await screen._process_events(events)
	if not is_instance_valid(screen) or not screen.is_inside_tree():
		return
	await screen.get_tree().process_frame
	_finish_action()


## Executes a validated player or AI choice through the same presentation path.
## The engine resolves outcomes; this component coordinates the screen-facing
## action lifecycle so manual, enemy and auto turns cannot drift apart.
func execute_action(skill_id: String, targets: Array) -> void:
	if is_authoritative_story():
		var uids: Array = []
		var skill := ContentDB.get_skill(skill_id)
		if skill == null:return
		if skill.target in ["single_ally","single_enemy"]:
			for index in targets:
				if int(index) >= 0 and int(index) < screen.engine.combatants.size():
					uids.append(screen.engine.combatants[int(index)].uid)
		await _send_spar_action({"kind":"skill","actorUid":_spar_actor,"skillId":skill_id,"targetUids":uids})
		return
	if not _begin_action():
		return
	var actor: Combatant = screen.engine.current_actor()
	if actor == null:
		_finish_action()
		return
	var played_skill: SkillDef = ContentDB.get_skill(skill_id)
	if played_skill != null and played_skill.ultimate:
		screen._show_banner(played_skill.display_name)
	var events := screen.engine.execute(screen.engine.current_actor_index, skill_id, targets)
	if events.is_empty():
		_finish_action()
		return
	await screen._process_events(events)
	if not is_instance_valid(screen) or not screen.is_inside_tree():
		return
	await screen.get_tree().process_frame
	_finish_action()

func _spar_request(payload: Dictionary) -> Dictionary:
	if _spar_busy or not spar_owner_is_current() or not AuthGateway.access_token_ready_for_connection():return {}
	if _spar_http == null:
		_spar_http = HTTPRequest.new()
		_spar_http.timeout = 35.0
		add_child(_spar_http)
	var owner := str(AuthGateway.current_player().get("id",""))
	_spar_busy = true
	var route := "/v1/gerald-story/" if is_online_gerald() else "/v1/tutorial-spar/"
	if is_online_garden():
		route = "/v1/royal-gate-story/" if screen.group_id in ["royal_gate_patrol_1", "royal_gate_patrol_2"] else "/v1/gardens-story/"
		payload = payload.duplicate(true)
		payload["groupId"] = screen.group_id
	var error := _spar_http.request(AuthGateway.api_base_url+route,PackedStringArray(["Authorization: Bearer "+AuthGateway.access_token_for_request(),"Content-Type: application/json"]),HTTPClient.METHOD_POST,JSON.stringify(payload))
	if error != OK:
		_spar_busy = false
		return {}
	var response: Array = await _spar_http.request_completed
	_spar_busy = false
	var data: Variant = JSON.parse_string((response[3] as PackedByteArray).get_string_from_utf8())
	if response[0] != HTTPRequest.RESULT_SUCCESS or response[1] != 200 or not data is Dictionary or not data.get("ok",false) or str(data.get("playerId","")) != owner or str(AuthGateway.current_player().get("id","")) != owner:return {}
	return data

func spar_owner_is_current() -> bool:
	return not _spar_owner.is_empty() and AuthGateway.is_authenticated() and _spar_owner == str(AuthGateway.current_player().get("id",""))

func _start_online_spar() -> void:
	_spar_id = ""
	_spar_sequence = 0
	_needs_story_recovery = false
	if not AuthGateway.access_token_ready_for_connection():
		EventBus.toast_requested.emit("Sign in to connect to the tutorial battle server.")
		# No server battle exists yet, so do not route through the authoritative
		# abandon path (which correctly requires a server-owned battle ID).
		# Close without rewards and leave the tutorial state unchanged.
		screen._claimed = true
		screen.closed.emit()
		screen.queue_free()
		return
	_spar_owner = str(AuthGateway.current_player().get("id","")) if AuthGateway.is_authenticated() else ""
	_spar_verified = false
	_server_rewards = {}
	_spar_unlock_notice = false
	screen._set_action_locked(true)
	screen._hint_label.text = "Connecting to the battle server..."
	var data := await _spar_request({"operation":"start"})
	if not is_instance_valid(screen) or not screen.is_inside_tree():return
	if data.is_empty():
		EventBus.toast_requested.emit("Could not connect to the battle server. Please retry.")
		screen._claim(false)
		return
	_spar_id = str(data.battleId)
	_spar_unlock_notice = bool(data.get("unlockNoticePending",false))
	_record_server_rewards(data)
	var view: Dictionary = data.view
	var players: Array = []
	var enemies := CombatFactory.enemy_units(screen.group_id, "village_solo" if is_online_gerald() else "")
	for row in view.units:
		if int(row.team) != CombatEngine.PLAYER_TEAM:continue
		var instance := CharacterInstance.from_dict({"char_id":str(row.charId),"uid":"server:"+str(row.charId),"level":1})
		var unit := CombatFactory.build_from_character(instance)
		if unit == null:continue
		unit.uid = str(row.uid)
		players.append(unit)
	if players.is_empty() or enemies.is_empty():
		screen._claim(false)
		return
	screen.engine = CombatEngine.new()
	screen.engine.setup(players,enemies)
	if not _apply_spar_view(view):
		EventBus.toast_requested.emit("Battle data does not match this game version.")
		screen._claim(false)
		return
	if screen._battlefield != null:screen._battlefield.setup(players,enemies)
	screen._build_roster(players)
	screen._log("[color=#e8c27a]Server-verified battle.[/color]")
	if is_online_gerald():
		for unit in enemies:
			if unit.is_boss:
				screen._title_label.text = "Boss encounter"
				if screen._boss_name_label != null: screen._boss_name_label.text = unit.display_name
				if screen._boss_hp_bar != null:
					screen._boss_hp_bar.max_value = unit.max_hp
					screen._boss_hp_bar.value = unit.hp
				if screen._boss_bar_container != null: screen._boss_bar_container.visible = true
				if int(view.sequence) == 0: screen._show_boss_intro(unit.display_name)
	screen._refresh_cards()
	if screen.engine.finished:
		await screen._result_component.finish_battle(_spar_verified)
	else:
		if int(view.sequence)==0:await screen._process_events(view.events)
		screen._update_turn_order()
		screen._set_action_locked(false)

func _validate_story_view(view: Dictionary) -> bool:
	if screen.engine == null or not view.get("units") is Array or not view.get("events") is Array:
		return false
	if str(view.get("status", "")) not in ["active", "victory", "defeat"] or not view.has("sequence") or not view.has("round"):
		return false
	if typeof(view.sequence) not in [TYPE_INT, TYPE_FLOAT] or typeof(view.round) not in [TYPE_INT, TYPE_FLOAT]:return false
	if not is_finite(float(view.sequence)) or not is_finite(float(view.round)):return false
	if float(view.sequence) != floorf(float(view.sequence)) or float(view.round) != floorf(float(view.round)) or int(view.sequence) < _spar_sequence or int(view.sequence) > 256 or int(view.round) < 1:return false
	if view.units.size() != screen.engine.combatants.size():return false
	var seen := {}
	var actor_found := false
	for row in view.units:
		if not row is Dictionary:return false
		var uid := str(row.get("uid", ""))
		var unit := screen.engine.get_by_uid(uid) as Combatant
		if unit == null or seen.has(uid) or str(row.get("charId", "")) != unit.def_id or int(row.get("team", -1)) != unit.team:return false
		seen[uid] = true
		for field in ["maxHp", "hp", "atk", "defense", "energy", "shield"]:
			if not row.has(field) or typeof(row[field]) not in [TYPE_INT, TYPE_FLOAT] or not is_finite(float(row[field])):return false
		if float(row.maxHp) <= 0 or float(row.hp) < 0 or float(row.hp) > float(row.maxHp):return false
		if not row.get("skills") is Array or not row.get("cooldowns") is Dictionary or not row.get("statuses") is Array or not row.get("phases") is Array or not row.has("ultimate") or not row.has("defending"):return false
		if uid == str(view.get("actorUid", "")) and unit.team == CombatEngine.PLAYER_TEAM and float(row.hp) > 0:actor_found = true
	return actor_found if view.status == "active" else str(view.get("actorUid", "")) == ""

func _apply_spar_view(view: Dictionary) -> bool:
	if not _validate_story_view(view):return false
	_spar_sequence = int(view.sequence)
	_spar_actor = str(view.actorUid)
	var engine := screen.engine
	engine.round_number = int(view.round)
	engine.finished = str(view.status)!="active"
	engine.winner_team = CombatEngine.PLAYER_TEAM if str(view.status)=="victory" else (CombatEngine.ENEMY_TEAM if engine.finished else -1)
	_spar_verified = str(view.status)=="victory"
	engine.current_actor_index = -1
	for row in view.units:
		var unit := engine.get_by_uid(str(row.uid)) as Combatant
		if unit == null:continue
		unit.max_hp = float(row.maxHp)
		unit.hp = float(row.hp)
		unit.atk = float(row.atk)
		unit.defense = float(row.defense)
		unit.energy = float(row.energy)
		unit.shield = float(row.shield)
		unit.skills = row.skills.duplicate()
		unit.ultimate = str(row.ultimate)
		unit.skill_cooldowns = row.cooldowns.duplicate(true)
		unit.statuses = row.statuses.duplicate(true)
		unit.triggered_phases = row.phases.duplicate()
		unit.defending = bool(row.defending)
		if unit.uid == _spar_actor:engine.current_actor_index = unit.combat_index
	screen._round_label.text = "Round %d" % engine.round_number
	return true

func _recover_story_view() -> bool:
	var data := await _spar_request({"operation":"resume","battleId":_spar_id})
	if not is_instance_valid(screen) or not screen.is_inside_tree():return false
	if data.is_empty() or str(data.get("battleId","")) != _spar_id or not data.get("view") is Dictionary or not _apply_spar_view(data.view):
		_finish_action()
		screen._hint_label.text = "Connection lost. Select an action to recover your battle first."
		return false
	_needs_story_recovery = false
	_spar_unlock_notice = bool(data.get("unlockNoticePending",false))
	_record_server_rewards(data)
	screen._refresh_cards()
	screen._update_turn_order()
	if screen.engine.finished:await screen._result_component.finish_battle(_spar_verified)
	_finish_action()
	if not screen.engine.finished:
		screen._hint_label.text = "Battle recovered. Select your next action."
	return true

func _send_spar_action(action: Dictionary) -> void:
	if _spar_busy or not spar_owner_is_current() or _spar_id.is_empty() or not _begin_action():return
	# After an uncertain request, restore the committed snapshot before any new action.
	if _needs_story_recovery:
		await _recover_story_view()
		return
	var payload := {"operation":"act","battleId":_spar_id,"sequence":_spar_sequence+1,"action":action}
	var data := await _spar_request(payload)
	if not is_instance_valid(screen) or not screen.is_inside_tree():return
	if data.is_empty() or str(data.get("battleId","")) != _spar_id or not data.get("view") is Dictionary or int(data.view.get("sequence", -1)) != int(payload.sequence) or not _apply_spar_view(data.view):
		_needs_story_recovery = true
		await _recover_story_view()
		return
	_record_server_rewards(data)
	_spar_unlock_notice = bool(data.get("unlockNoticePending",false))
	await screen._process_events(data.view.events)
	if not is_instance_valid(screen) or not screen.is_inside_tree():return
	if screen.engine.finished and not screen._resolved:await screen._result_component.finish_battle(_spar_verified)
	_finish_action()

func acknowledge_spar_unlock() -> void:
	if not _spar_unlock_notice or not _spar_verified:return
	var data := await _spar_request({"operation":"ack_unlock","battleId":_spar_id})
	if not data.is_empty():_spar_unlock_notice = false

func abandon_online_spar() -> bool:
	if _spar_id.is_empty() or not spar_owner_is_current() or (screen.engine != null and screen.engine.finished):return true
	if _spar_busy:return false
	var data := await _spar_request({"operation":"abandon","battleId":_spar_id})
	return not data.is_empty() and str(data.get("status", "")) == "abandoned"
func _record_server_rewards(data: Dictionary) -> void:
	var rewards: Variant = data.get("rewards")
	_server_rewards = rewards.duplicate(true) if rewards is Dictionary else {}
