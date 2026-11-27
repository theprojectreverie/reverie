extends Node
## Internal headless replay worker. Inputs originate from the server database,
## never from client-provided character stats, seed, enemy AI or rewards.
const MAX_ACTIONS := 256
const MAX_STEPS := 4096
const MARKER := "STORY_COMBAT_RESULT "
const MAX_BATCH := 32
var _batch_mode := false

func _ready() -> void:
	call_deferred("_run")

func _finish(value: Dictionary) -> void:
	print(MARKER + JSON.stringify(value))
	if not _batch_mode:
		get_tree().quit(0)

func _run() -> void:
	if DisplayServer.get_name() != "headless" or OS.get_environment("REVERIE_E2E_DISABLE_LOCAL_SAVE") != "1" or OS.get_environment("REVERIE_STORY_WORKER") != "1":
		_finish({"ok":false,"reason":"worker_environment_required"})
		return
	var args := OS.get_cmdline_user_args()
	if args.size() != 1 and not (args.size() == 2 and args[0] == "--batch"):
		_finish({"ok":false,"reason":"input_missing"})
		return
	var input_path := args[args.size() - 1]
	if not FileAccess.file_exists(input_path):
		_finish({"ok":false,"reason":"input_missing"})
		return
	var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(input_path))
	if args.size() == 2:
		if not data is Array or data.is_empty() or data.size() > MAX_BATCH:
			_finish({"ok":false,"reason":"invalid_batch"})
			return
		_batch_mode = true
		for job in data:
			_simulate(job)
		get_tree().quit(0)
		return
	_simulate(data)

func _simulate(data: Variant) -> void:
	if not data is Dictionary or not data.get("party") is Array or not data.get("actions") is Array:
		_finish({"ok":false,"reason":"invalid_input"})
		return
	var raw_defs: Variant=data.get("definitions",{})
	if not raw_defs is Dictionary:
		_finish({"ok":false,"reason":"invalid_live_definitions"})
		return
	var defs:=ContentDB.validated_live_definitions(raw_defs)
	if defs.size()!=raw_defs.size():
		_finish({"ok":false,"reason":"invalid_live_definitions"})
		return
	ContentDB.install_live_definitions(defs)
	var group := str(data.get("groupId",""))
	var rows: Array = data.party
	var actions: Array = data.actions
	if rows.is_empty() or rows.size() > 4 or actions.size() > MAX_ACTIONS or ContentDB.get_enemy_group(group).is_empty():
		_finish({"ok":false,"reason":"invalid_battle"})
		return
	var instances: Array = []
	var ids: Array = []
	GameState.roster_domain.roster = []
	GameState.gear_levels = {}
	GameState.gear_rerolls = {}
	for row in rows:
		var id := str(row.get("char_id",""))
		var definition := ContentDB.get_character(id)
		if definition == null or id in ids:
			_finish({"ok":false,"reason":"invalid_party"})
			return
		ids.append(id)
		var instance_data: Dictionary = row.duplicate(true)
		instance_data["uid"] = "account:" + id
		instance_data["equipment"] = {}
		for gear in row.get("equipment",[]):
			var slot := str(gear.get("slot",""))
			if slot not in CharacterInstance.SLOTS:
				_finish({"ok":false,"reason":"invalid_gear"})
				return
			instance_data.equipment[slot] = str(gear.item_id)
			var key := str(instance_data.uid) + "|" + slot
			GameState.gear_levels[key] = int(gear.get("enhancement_level",0))
			GameState.gear_rerolls[key] = {"stat":str(gear.get("reroll_stat","")),"value":float(gear.get("reroll_value",0) if gear.get("reroll_value") != null else 0),"item_id":str(gear.item_id)}
		# The isolated worker uses local gear lookup, with no account transport.
		instance_data.uid = "server:" + id
		for slot in instance_data.equipment:
			var source := "account:" + id + "|" + str(slot)
			var dest := str(instance_data.uid) + "|" + str(slot)
			GameState.gear_levels[dest] = GameState.gear_levels[source]
			GameState.gear_rerolls[dest] = GameState.gear_rerolls[source]
		var instance := CharacterInstance.from_dict(instance_data)
		instances.append(instance)
		GameState.roster_domain.roster.append(instance)
	var collection_count := maxi(instances.size(),int(data.get("collectionCount",instances.size())))
	var bonus := 1.0 + minf(0.15,0.01 * floori(collection_count / 3.0))
	var units: Array = []
	for instance in instances:
		units.append(CombatFactory.build_from_character(instance,bonus))
	for bond in preload("res://scripts/gacha/character_upgrade_card.gd").active_bonds(instances):
		for unit in units:
			if unit.def_id in bond.members:
				if bond.stat == "def": unit.defense *= float(bond.multiplier)
				elif bond.stat == "atk": unit.atk *= float(bond.multiplier)
	var profile := "village_solo" if group == "gerald_boss_encounter" else ("story_tower" if group == "revienna_encounter" else "")
	var enemies := CombatFactory.enemy_units(group,profile)
	if enemies.is_empty():
		_finish({"ok":false,"reason":"invalid_enemy_group"})
		return
	var engine := CombatEngine.new()
	engine.setup(units,enemies,int(data.get("seed",0)))
	var events := engine.start()
	var last_events: Array = events.duplicate(true)
	var consumed := 0
	var steps := 0
	while not engine.finished:
		steps += 1
		if steps > MAX_STEPS or engine.current_actor_index < 0 or engine.current_actor_index >= engine.combatants.size():
			_finish({"ok":false,"reason":"combat_step_limit"})
			return
		var actor: Combatant = engine.combatants[engine.current_actor_index]
		if actor.team == CombatEngine.ENEMY_TEAM:
			var decision := CombatAI.choose(engine,engine.current_actor_index)
			var enemy_events: Array = []
			if str(decision.get("skill_id","")) != "":
				enemy_events = engine.execute(engine.current_actor_index,str(decision.skill_id),decision.targets)
			if enemy_events.is_empty():
				enemy_events = engine.advance_turn()
			last_events.append_array(enemy_events)
			continue
		if consumed == actions.size():
			break
		var action: Dictionary = actions[consumed]
		if str(action.get("actorUid","")) != actor.uid:
			_finish({"ok":false,"reason":"wrong_actor","actionIndex":consumed})
			return
		var kind := str(action.get("kind",""))
		var player_events: Array = []
		if kind == "defend":
			player_events = engine.defend(engine.current_actor_index)
		elif kind == "end_turn":
			player_events = engine.end_turn(engine.current_actor_index)
		elif kind == "skill":
			var skill_id := str(action.get("skillId",""))
			var skill := ContentDB.get_skill(skill_id)
			var is_bond := CombatEngine.BOND_PAIRS.has(skill_id)
			if not is_bond and (skill == null or (skill_id not in actor.skills and skill_id != actor.ultimate)):
				_finish({"ok":false,"reason":"skill_not_equipped","actionIndex":consumed})
				return
			var targets: Array = []
			var requested: Array = action.get("targetUids",[])
			if not is_bond and skill.target in ["single_ally","single_enemy"]:
				if requested.size() != 1:
					_finish({"ok":false,"reason":"invalid_target","actionIndex":consumed})
					return
				for target in engine.combatants:
					if target.uid == str(requested[0]) and target.is_alive() and target.team == (actor.team if skill.target == "single_ally" else 1 - actor.team):
						targets.append(target.combat_index)
				if targets.size() != 1:
					_finish({"ok":false,"reason":"invalid_target","actionIndex":consumed})
					return
			elif not requested.is_empty():
				_finish({"ok":false,"reason":"invalid_target","actionIndex":consumed})
				return
			player_events = engine.execute(engine.current_actor_index,skill_id,targets)
		if player_events.is_empty():
			_finish({"ok":false,"reason":"illegal_action","actionIndex":consumed})
			return
		consumed += 1
		last_events = player_events.duplicate(true)
	if consumed != actions.size():
		_finish({"ok":false,"reason":"battle_already_finished"})
		return
	var snapshot: Array = []
	for unit in engine.combatants:
		snapshot.append({"uid":unit.uid,"charId":unit.def_id,"team":unit.team,"hp":unit.hp,"maxHp":unit.max_hp,"atk":unit.atk,"defense":unit.defense,"energy":unit.energy,"shield":unit.shield,"skills":unit.skills,"ultimate":unit.ultimate,"cooldowns":unit.skill_cooldowns,"statuses":unit.statuses,"phases":unit.triggered_phases,"defending":unit.defending,"ascension":unit.ascension})
	var current := "" if engine.finished else str(engine.combatants[engine.current_actor_index].uid)
	_finish({"ok":true,"status":("victory" if engine.winner_team == CombatEngine.PLAYER_TEAM else "defeat") if engine.finished else "active","actorUid":current,"round":engine.round_number,"sequence":consumed,"units":snapshot,"events":last_events,"bondGauges":engine.bond_gauges,"bondUses":engine.bond_uses})
