class_name EquipmentStatModifiers
extends RefCounted

const SET_BONUSES := {
	"greenward_wayfarer": {
		2: {"hp": 40.0, "def": 4.0},
		3: {"spd": 5.0, "crit": 0.02}
	}
}

static func for_character(uid: String) -> Dictionary:
	return _compute(uid)


static func set_bonus_for_character(uid: String) -> Dictionary:
	var bonuses := {"hp": 0.0, "atk": 0.0, "def": 0.0, "spd": 0.0, "crit": 0.0, "crit_dmg": 0.0}
	var instance: CharacterInstance = GameState.roster_domain.gameplay_instance(uid)
	if instance == null:
		return bonuses
	var equipped_sets: Dictionary = {}
	for slot in CharacterInstance.SLOTS:
		var item_id := instance.equipped_item(slot)
		if item_id.is_empty():
			continue
		var item := ContentDB.get_item(item_id)
		var rolled: Dictionary = GameState.gear_rerolls.get(uid + "|" + slot, {})
		if uid.begins_with("account:"):
			var gear: Dictionary = GameState.roster_domain.account_gear(uid, slot)
			rolled = {"stat": gear.get("reroll_stat", ""), "value": gear.get("reroll_value", 0), "item_id": gear.get("item_id", "")}
		var rolled_stat := str(rolled.get("stat", ""))
		var base := float(item.get("stats", {}).get(rolled_stat, 0.0))
		if bonuses.has(rolled_stat) and base > 0.0 and str(rolled.get("item_id", item_id)) == item_id:
			var maximum := maxf(0.001 if rolled_stat in ["crit", "crit_dmg"] else 1.0, base * 0.10)
			bonuses[rolled_stat] += clampf(float(rolled.get("value", 0.0)), 0.0, maximum)
		var set_id := str(item.get("set_id", ""))
		if not set_id.is_empty():
			equipped_sets[set_id] = int(equipped_sets.get(set_id, 0)) + 1
	for set_id in equipped_sets:
		var thresholds: Dictionary = SET_BONUSES.get(set_id, {})
		var count := int(equipped_sets[set_id])
		for threshold in thresholds:
			if count < int(threshold):
				continue
			var bonus: Dictionary = thresholds[threshold]
			for stat in bonus:
				bonuses[str(stat)] = float(bonuses.get(str(stat), 0.0)) + float(bonus[stat])
	return bonuses


static func _compute(uid: String) -> Dictionary:
	var total := {"hp": 0.0, "atk": 0.0, "def": 0.0, "spd": 0.0, "crit": 0.0, "crit_dmg": 0.0}
	var instance: CharacterInstance = GameState.roster_domain.gameplay_instance(uid)
	if instance == null:
		return total
	var equipped_sets: Dictionary = {}
	for slot in CharacterInstance.SLOTS:
		var item_id := instance.equipped_item(slot)
		if item_id.is_empty():
			continue
		var item := ContentDB.get_item(item_id)
		var set_id := str(item.get("set_id", ""))
		if not set_id.is_empty():
			equipped_sets[set_id] = int(equipped_sets.get(set_id, 0)) + 1
		var stats: Dictionary = item.get("stats", {})
		var enhancement_mult := 1.0 + 0.08 * float(GameState.roster_domain.gear_level(uid, slot))
		for k in stats.keys():
			var key := str(k)
			if not total.has(key):
				total[key] = 0.0
			total[key] = float(total[key]) + float(stats[k]) * enhancement_mult
	for set_id in equipped_sets:
		var thresholds: Dictionary = SET_BONUSES.get(set_id, {})
		var count := int(equipped_sets[set_id])
		for threshold in thresholds:
			if count < int(threshold):
				continue
			var bonus: Dictionary = thresholds[threshold]
			for stat in bonus:
				var key := str(stat)
				if not total.has(key):
					total[key] = 0.0
				total[key] = float(total[key]) + float(bonus[stat])
	return total
