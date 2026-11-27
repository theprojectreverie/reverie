class_name Combatant
extends RefCounted
## One unit in a battle. Pure data + status math; no scene access.

var uid: String = ""
var def_id: String = ""
var display_name: String = ""
var team: int = 0                    # 0 = player, 1 = enemy
var element: String = "neutral"
var rarity: String = "common"
var role: String = ""
var level: int = 1
var ascension: int = 0
var combat_index: int = -1

var max_hp: float = 100.0
var hp: float = 100.0
var atk: float = 10.0
var defense: float = 10.0
var speed: float = 10.0
var crit_chance: float = 0.05
var crit_mult: float = 1.6

var energy: float = 0.0
var max_energy: float = 100.0
var shield: float = 0.0
var bond_guardian: WeakRef
var defending: bool = false

var skills: Array = []
var skill_levels: Dictionary = {}
var ultimate: String = ""
var passive_id: String = ""
var equipment_element: String = ""
var palette: Dictionary = {}
var is_boss: bool = false
var phases: Array = []
var triggered_phases: Array = []

var statuses: Array = []             # [{id, turns, potency}]
var skill_cooldowns: Dictionary = {}  # skill_id -> turns remaining (plus active-turn offset)


func skill_level(skill_id: String) -> int:
	return clampi(int(skill_levels.get(skill_id, 1)), 1, CharacterInstance.MAX_SKILL_LEVEL)


func skill_power_multiplier(skill_id: String) -> float:
	return 1.0 + 0.05 * (skill_level(skill_id) - 1)


func is_alive() -> bool:
	return hp > 0.0


func hp_ratio() -> float:
	return clampf(hp / maxf(1.0, max_hp), 0.0, 1.0)


func status_total(status_id: String) -> float:
	var total := 0.0
	for status in statuses:
		if str(status.get("id", "")) == status_id:
			total += float(status.get("potency", 0.0))
	return total


func has_status(status_id: String) -> bool:
	for status in statuses:
		if str(status.get("id", "")) == status_id:
			return true
	return false


func effective_atk() -> float:
	var multiplier := 1.0 + status_total("atk_up") - status_total("atk_down")
	return maxf(1.0, atk * clampf(multiplier, 0.25, 3.0))


func effective_defense() -> float:
	var multiplier := 1.0 + status_total("def_up") - status_total("def_down")
	return maxf(1.0, defense * clampf(multiplier, 0.2, 3.0))


func effective_speed() -> float:
	var multiplier := 1.0 + status_total("spd_up") - status_total("spd_down")
	return maxf(1.0, speed * clampf(multiplier, 0.25, 3.0))


func ultimate_ready() -> bool:
	return not ultimate.is_empty() and energy >= max_energy


func cooldown_remaining(skill_id: String) -> int:
	return maxi(0, int(skill_cooldowns.get(skill_id, 0)))


func is_skill_on_cooldown(skill_id: String) -> bool:
	return int(skill_cooldowns.get(skill_id, 0)) > 0


func start_skill_cooldown(skill_id: String, turns: int) -> void:
	if turns <= 0:
		skill_cooldowns.erase(skill_id)
		return
	# The extra tick is consumed at the start of the current actor's next turn,
	# so a value of 2 blocks two complete future turns.
	skill_cooldowns[skill_id] = turns + 1


func tick_skill_cooldowns() -> Array:
	var ready: Array = []
	for skill_id in skill_cooldowns.keys():
		var remaining := int(skill_cooldowns[skill_id]) - 1
		if remaining <= 0:
			skill_cooldowns.erase(skill_id)
			ready.append(str(skill_id))
		else:
			skill_cooldowns[skill_id] = remaining
	return ready


func add_energy(amount: float) -> void:
	energy = clampf(energy + amount, 0.0, max_energy)


func apply_status(status_id: String, turns: int, potency: float) -> void:
	if status_id == "shield":
		shield += max_hp * potency
		return
	if status_id == "cleanse":
		return
	for status in statuses:
		if str(status.get("id", "")) == status_id:
			status.turns = maxi(int(status.get("turns", 0)), turns)
			status.potency = maxf(float(status.get("potency", 0.0)), potency)
			return
	statuses.append({ "id": status_id, "turns": turns, "potency": potency })


func cleanse() -> void:
	var kept: Array = []
	for status in statuses:
		var status_id := str(status.get("id", ""))
		if status_id in ["atk_up", "def_up", "spd_up", "regen", "bond_guard", "bond_survive"]:
			kept.append(status)
	statuses = kept


func take_damage(amount: float, allow_redirect: bool = true) -> Dictionary:
	var incoming := maxf(0.0, amount)
	var bond_events: Array = []
	if allow_redirect and incoming > 0.0 and has_status("bond_guard") and bond_guardian != null:
		var guardian := bond_guardian.get_ref() as Combatant
		if guardian != null and guardian != self and guardian.is_alive():
			var transfer := incoming * 0.35
			incoming -= transfer
			var redirected := guardian.take_damage(transfer, false)
			bond_events.append({"type":"status_tick","status":"bond_guard","target_uid":guardian.uid,"target_name":guardian.display_name,"amount":roundi(redirected.damage)})
			bond_events.append_array(redirected.get("bond_events", []))
			if redirected.dead:
				bond_events.append({"type":"death","target_uid":guardian.uid,"target_name":guardian.display_name})
	var absorbed := minf(shield, incoming)
	shield -= absorbed
	incoming -= absorbed
	var before := hp
	hp = maxf(0.0, hp - incoming)
	if hp <= 0.0 and before > 0.0 and has_status("bond_survive"):
		hp = 1.0
		statuses = statuses.filter(func(status): return str(status.get("id", "")) != "bond_survive")
		bond_events.append({"type":"status","status":"bond_survive","target_uid":uid,"target_name":display_name,"turns":0})
	return { "damage": incoming, "absorbed": absorbed, "dead": hp <= 0.0, "bond_events": bond_events }


func heal(amount: float) -> float:
	var before := hp
	hp = minf(max_hp, hp + maxf(0.0, amount))
	return hp - before


func status_names() -> Array:
	var names: Array = []
	for status in statuses:
		names.append(str(status.get("id", "")))
	return names
