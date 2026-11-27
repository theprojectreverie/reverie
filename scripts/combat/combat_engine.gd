class_name CombatEngine
extends RefCounted
## Deterministic, scene-independent turn-based battle engine.
##
## The engine owns no nodes and no UI. It consumes Combatants and Skills and
## returns an event stream that the battle scene animates. That separation is
## deliberate: the same engine will run on an authoritative server for PvP/raids
## while the client only replays validated events.

const PLAYER_TEAM := 0
const ENEMY_TEAM := 1
const DAMAGE_SCALE := 1.6
const CRIT_MULTIPLIER := 1.6
const DEFEND_DAMAGE_REDUCTION := 0.5
# Equipment element resonance: a skill matching the equipped element deals 8%
# more damage; a weapon matching the wielder's own element adds another 4%.
const EQUIPMENT_RESONANCE := 1.08
const EQUIPMENT_ATTUNEMENT := 1.04

var combatants: Array = []
var order: Array = []
var turn_pointer: int = 0
var round_number: int = 1
var current_actor_index: int = -1
var finished: bool = false
var winner_team: int = -1
var log: Array = []
var rng := RandomNumberGenerator.new()

var _dawnkeeper_used: Dictionary = {}
const BOND_PAIRS := {"beyond_death": ["gerald_mythic", "lilith_mythic"], "eternal_eclipse": ["cassien_mythic", "ravienna_mythic"]}
const BOND_NAMES := {"beyond_death": "Beyond Death", "eternal_eclipse": "Eternal Eclipse"}
var bond_gauges: Dictionary = {}
var bond_uses: Dictionary = {}

func bond_pair(id: String) -> Array:
	var pair: Array = []
	if not BOND_PAIRS.has(id): return pair
	for member in BOND_PAIRS[id]:
		for unit in living(PLAYER_TEAM):
			if unit.def_id == member and unit.ascension == CharacterInstance.MAX_ASCENSION:
				pair.append(unit)
				break
	return pair if pair.size() == 2 else []

func bond_for(actor: Combatant) -> String:
	if actor == null or actor.team != PLAYER_TEAM: return ""
	for id in BOND_PAIRS:
		if actor.def_id in BOND_PAIRS[id] and bond_pair(id).size() == 2: return id
	return ""

func bond_ready(actor: Combatant, id: String) -> bool:
	return not finished and actor != null and actor.combat_index == current_actor_index and bond_for(actor) == id and not id.is_empty() and int(bond_gauges.get(id, 0)) >= 100 and int(bond_uses.get(id, 0)) < 2

func _charge_bond(actor: Combatant) -> void:
	var id := bond_for(actor)
	if not id.is_empty() and int(bond_uses.get(id, 0)) < 2:
		bond_gauges[id] = mini(100, int(bond_gauges.get(id, 0)) + 25)

func execute_bond(actor: Combatant, id: String) -> Array:
	if not bond_ready(actor, id): return []
	var pair := bond_pair(id)
	bond_gauges[id] = 0
	bond_uses[id] = int(bond_uses.get(id, 0)) + 1
	var events: Array = [{"type":"bond", "bond_id":id, "skill_name":BOND_NAMES[id], "actor_uid":actor.uid, "member_uids":_uids_of(pair)}]
	_append_log(str(BOND_NAMES[id]))
	if id == "beyond_death":
		for ally in living(actor.team):
			var healed: float = ally.heal(ally.max_hp * 0.5)
			var added: float = ally.max_hp * 0.3
			ally.shield += added
			events.append({"type":"heal","target_uid":ally.uid,"target_name":ally.display_name,"amount":roundi(healed)})
			events.append({"type":"shield","target_uid":ally.uid,"target_name":ally.display_name,"amount":roundi(added)})
			if ally != pair[0]:
				ally.bond_guardian = weakref(pair[0])
				ally.apply_status("bond_guard", 2, 0.35)
				events.append({"type":"status","target_uid":ally.uid,"target_name":ally.display_name,"status":"bond_guard","turns":2})
		for sibling in pair:
			sibling.apply_status("bond_survive", 2, 1.0)
			events.append({"type":"status","target_uid":sibling.uid,"target_name":sibling.display_name,"status":"bond_survive","turns":2})
	else:
		var combined: float = pair[0].effective_atk() + pair[1].effective_atk()
		var dealt := 0.0
		for foe in living(1 - actor.team):
			if not foe.is_alive(): continue
			var before: float = foe.hp
			var raw: float = 4.5 * combined * combined / (combined + unit_defense(foe))
			var result: Dictionary = foe.take_damage(maxf(1.0, roundf(raw * incoming_multiplier(foe))))
			dealt += before - foe.hp
			events.append({"type":"damage","actor_uid":actor.uid,"target_uid":foe.uid,"target_name":foe.display_name,"amount":roundi(result.damage),"absorbed":roundi(result.absorbed),"crit":false,"element":"neutral","skill_id":id,"element_mult":1.0,"advantage":""})
			events.append_array(result.get("bond_events", []))
			if foe.is_alive():
				foe.apply_status("def_down", 2, 0.4)
				foe.apply_status("eclipse_curse", 3, 0.05)
				for status in ["def_down","eclipse_curse"]:
					events.append({"type":"status","target_uid":foe.uid,"target_name":foe.display_name,"status":status,"turns":2 if status == "def_down" else 3})
				events.append_array(_check_boss_phases(foe))
			else:
				events.append({"type":"death","target_uid":foe.uid,"target_name":foe.display_name})
		for ally in living(actor.team):
			ally.cleanse()
			events.append({"type":"status","target_uid":ally.uid,"target_name":ally.display_name,"status":"cleanse","turns":0})
		for member in pair:
			var healed: float = member.heal(dealt * 0.125)
			events.append({"type":"heal","target_uid":member.uid,"target_name":member.display_name,"amount":roundi(healed)})
	if _check_finish(): return events + _finish_events()
	return events + advance_turn()

var skill_resolver := CombatSkillResolver.new()

func _init() -> void:
	skill_resolver.bind(self)



func _apply_skill(actor: Combatant, skill: SkillDef, target: Combatant) -> Array:
	return skill_resolver.apply_skill(actor, skill, target)


func _deal_damage(actor: Combatant, skill: SkillDef, target: Combatant) -> Array:
	return skill_resolver.deal_damage(actor, skill, target)


func _check_boss_phases(unit: Combatant) -> Array:
	return skill_resolver.check_boss_phases(unit)


func setup(player_units: Array, enemy_units: Array, battle_seed: int = 12345) -> void:
	combatants.clear()
	for unit in player_units:
		unit.team = PLAYER_TEAM
		combatants.append(unit)
	for unit in enemy_units:
		unit.team = ENEMY_TEAM
		combatants.append(unit)
	for index in combatants.size():
		combatants[index].combat_index = index
		combatants[index].triggered_phases.clear()
		combatants[index].skill_cooldowns.clear()
		combatants[index].defending = false
		combatants[index].bond_guardian = null
		combatants[index].statuses = combatants[index].statuses.filter(func(status): return str(status.get("id","")) not in ["bond_guard","bond_survive","eclipse_curse"])
	rng.seed = battle_seed
	finished = false
	winner_team = -1
	round_number = 1
	log.clear()
	_dawnkeeper_used.clear()
	bond_gauges.clear()
	bond_uses.clear()
	_apply_battle_start_passives()
	_build_order()
	turn_pointer = -1
	current_actor_index = -1


func start() -> Array:
	if combatants.is_empty():
		return []
	_build_order()
	turn_pointer = -1
	return advance_turn()


func advance_turn() -> Array:
	if finished:
		return []
	var events: Array = []
	var guard := 0
	var max_guard := maxi(4, combatants.size() * 3)
	while guard < max_guard:
		guard += 1
		turn_pointer += 1
		if turn_pointer >= order.size():
			round_number += 1
			_build_order()
			turn_pointer = 0
			events.append({ "type": "round", "round": round_number })
		if order.is_empty():
			_check_finish()
			return events + _finish_events()
		var index: int = int(order[turn_pointer])
		var actor: Combatant = combatants[index]
		if not actor.is_alive():
			continue
		current_actor_index = index
		var beginning := _begin_actor_turn(actor)
		events.append_array(beginning.events)
		if _check_finish():
			return events + _finish_events()
		if beginning.skipped:
			continue
		events.append({
			"type": "turn",
			"actor_uid": actor.uid,
			"actor_name": actor.display_name,
			"actor_index": index,
			"round": round_number,
		})
		return events
	current_actor_index = -1
	return events


func _begin_actor_turn(actor: Combatant) -> Dictionary:
	var result := CombatTurnLifecycleResolver.begin_actor_turn(actor)
	for message in result.get("log_messages", []):
		_append_log(str(message))
	return {
		"events": result.get("events", []),
		"skipped": bool(result.get("skipped", true)),
	}

func execute(actor_index: int, skill_id: String, target_indices: Array = []) -> Array:
	var events: Array = []
	if finished:
		return events
	if actor_index < 0 or actor_index >= combatants.size():
		return events
	if actor_index != current_actor_index:
		return events
	var actor: Combatant = combatants[actor_index]
	if not actor.is_alive():
		return events
	if BOND_PAIRS.has(skill_id):
		return execute_bond(actor, skill_id) if target_indices.is_empty() else []
	var skill: SkillDef = ContentDB.get_skill(skill_id)
	if skill == null:
		_append_log("Unknown skill: " + skill_id)
		return events
	if actor.is_skill_on_cooldown(skill.id):
		return events
	# Validate target availability before consuming energy or starting cooldowns.
	# Invalid/empty target rules must leave the actor's resources untouched.
	var targets := resolve_targets(actor, skill, target_indices)
	if targets.is_empty():
		return events
	if skill.ultimate:
		if not actor.ultimate_ready():
			return events
	else:
		actor.add_energy(skill.energy_gain)
	actor.start_skill_cooldown(skill.id, skill.cooldown_turns)
	if skill.ultimate:
		actor.energy = 0.0
	events.append({
		"type": "action",
		"actor_uid": actor.uid,
		"actor_name": actor.display_name,
		"actor_index": actor_index,
		"skill_id": skill.id,
		"skill_name": skill.display_name,
		"element": skill.element,
		"ultimate": skill.ultimate,
		"animation_key": skill.animation_key,
		"vfx_key": skill.vfx_key,
		"target_uids": _uids_of(targets),
	})
	_append_log("%s uses %s." % [actor.display_name, skill.display_name])

	for target in targets:
		if not target.is_alive() and skill.kind != "heal":
			continue
		events.append_array(_apply_skill(actor, skill, target))

	_charge_bond(actor)
	if _check_finish():
		return events + _finish_events()
	events.append_array(advance_turn())
	return events


func defend(actor_index: int) -> Array:
	if finished or actor_index < 0 or actor_index >= combatants.size() or actor_index != current_actor_index:
		return []
	var actor: Combatant = combatants[actor_index]
	if not actor.is_alive() or actor.team != PLAYER_TEAM:
		return []
	actor.defending = true
	_append_log("%s takes a defensive stance." % actor.display_name)
	var events: Array = [{
		"type": "defend",
		"actor_uid": actor.uid,
		"actor_name": actor.display_name,
	}]
	events.append_array(advance_turn())
	return events


func end_turn(actor_index: int) -> Array:
	if finished or actor_index < 0 or actor_index >= combatants.size() or actor_index != current_actor_index:
		return []
	var actor: Combatant = combatants[actor_index]
	if not actor.is_alive() or actor.team != PLAYER_TEAM:
		return []
	_append_log("%s ends their turn." % actor.display_name)
	var events: Array = [{
		"type": "end_turn",
		"actor_uid": actor.uid,
		"actor_name": actor.display_name,
	}]
	events.append_array(advance_turn())
	return events


func resolve_targets(actor: Combatant, skill: SkillDef, chosen: Array) -> Array:
	var result: Array = []
	var enemy_team := 1 - actor.team
	match skill.target:
		"self":
			result = [actor]
		"all_enemies":
			result = living(enemy_team)
		"all_allies":
			result = living(actor.team)
		"single_ally":
			var ally := _pick_valid(chosen, actor.team)
			if ally == null:
				ally = _lowest_health(actor.team)
			result = [ally] if ally != null else []
		"single_enemy":
			var foe := _pick_valid(chosen, enemy_team)
			if foe == null:
				foe = _first_living(enemy_team)
			result = [foe] if foe != null else []
		_:
			result = []
	return result


func _pick_valid(chosen: Array, team: int) -> Combatant:
	for value in chosen:
		var index := int(value)
		if index >= 0 and index < combatants.size():
			var candidate: Combatant = combatants[index]
			if candidate.team == team and candidate.is_alive():
				return candidate
	return null


func _first_living(team: int) -> Combatant:
	for unit in living(team):
		return unit
	return null


func _lowest_health(team: int) -> Combatant:
	var best: Combatant = null
	for unit in living(team):
		if best == null or unit.hp_ratio() < best.hp_ratio():
			best = unit
	return best


func _check_finish() -> bool:
	if finished:
		return true
	if living(ENEMY_TEAM).is_empty():
		finished = true
		winner_team = PLAYER_TEAM
		return true
	if living(PLAYER_TEAM).is_empty():
		finished = true
		winner_team = ENEMY_TEAM
		return true
	return false


func _finish_events() -> Array:
	if not finished:
		return []
	if winner_team == PLAYER_TEAM:
		_append_log("Victory.")
		return [{ "type": "victory", "winner_team": winner_team }]
	_append_log("Defeat.")
	return [{ "type": "defeat", "winner_team": winner_team }]


func living(team: int) -> Array:
	var result: Array = []
	for unit in combatants:
		if unit.team == team and unit.is_alive():
			result.append(unit)
	return result


func living_indices(team: int) -> Array:
	var result: Array = []
	for index in combatants.size():
		var unit: Combatant = combatants[index]
		if unit.team == team and unit.is_alive():
			result.append(index)
	return result


func current_actor() -> Combatant:
	if current_actor_index < 0 or current_actor_index >= combatants.size():
		return null
	return combatants[current_actor_index]


func get_by_uid(uid_value: String) -> Combatant:
	for unit in combatants:
		if unit.uid == uid_value:
			return unit
	return null


# ------------------------------------------------------------ passive helpers

func _apply_battle_start_passives() -> void:
	for team in [PLAYER_TEAM, ENEMY_TEAM]:
		if _team_has_passive(team, "small_miracles"):
			for unit in living(team):
				unit.add_energy(PassiveEffects.SMALL_MIRACLES_ENERGY)


func _has_passive(unit: Combatant, passive_id: String) -> bool:
	return CombatPassiveResolver.has_passive(unit, passive_id)


func _team_has_passive(team: int, passive_id: String) -> bool:
	return CombatPassiveResolver.team_has_passive(living(team), passive_id)


func _team_has_passive_excluding(team: int, passive_id: String, excluded: Combatant) -> bool:
	return CombatPassiveResolver.team_has_passive_excluding(living(team), passive_id, excluded)


func _has_debuff(unit: Combatant) -> bool:
	return CombatPassiveResolver.has_debuff(unit)


func unit_speed(unit: Combatant) -> float:
	return CombatPassiveResolver.unit_speed(unit, living(unit.team))


func unit_defense(unit: Combatant) -> float:
	return CombatPassiveResolver.unit_defense(unit)


## Damage multiplier from the attacker's passives and equipment resonance.
func outgoing_multiplier(actor: Combatant, skill_element: String, target: Combatant) -> float:
	return CombatPassiveResolver.outgoing_multiplier(actor, skill_element, target, EQUIPMENT_RESONANCE, EQUIPMENT_ATTUNEMENT)

## Damage multiplier applied to incoming damage from the defender's passives.
func incoming_multiplier(target: Combatant) -> float:
	var multiplier := CombatPassiveResolver.incoming_multiplier(target, living(target.team))
	if target.defending:
		multiplier *= 1.0 - DEFEND_DAMAGE_REDUCTION
	return multiplier

func _build_order() -> void:
	var alive_indices := living_indices(PLAYER_TEAM) + living_indices(ENEMY_TEAM)
	alive_indices.sort_custom(func(a, b):
		var unit_a: Combatant = combatants[a]
		var unit_b: Combatant = combatants[b]
		var speed_a := unit_speed(unit_a)
		var speed_b := unit_speed(unit_b)
		if is_equal_approx(speed_a, speed_b):
			return a < b
		return speed_a > speed_b
	)
	order = alive_indices


func upcoming_turns(count: int = 6) -> Array:
	var result: Array = []
	var preview_order := order.duplicate()
	var pointer := turn_pointer
	var safety := 0
	while result.size() < count and safety < count * 3 + 6:
		safety += 1
		pointer += 1
		if pointer >= preview_order.size():
			preview_order = living_indices(PLAYER_TEAM) + living_indices(ENEMY_TEAM)
			preview_order.sort_custom(func(a, b):
				return unit_speed(combatants[a]) > unit_speed(combatants[b])
			)
			pointer = 0
		if preview_order.is_empty():
			break
		var unit: Combatant = combatants[int(preview_order[pointer])]
		if unit.is_alive():
			result.append({
				"uid": unit.uid,
				"name": unit.display_name,
				"team": unit.team,
				"element": unit.element,
			})
	return result


func _uids_of(units: Array) -> Array:
	var result: Array = []
	for unit in units:
		result.append(unit.uid)
	return result


func _append_log(message: String) -> void:
	log.append(message)
	if log.size() > 80:
		log.pop_front()
