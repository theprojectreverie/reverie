class_name ItemUpgrade
extends RefCounted

static func get_config_for_slot(slot: String, item_id: String = "") -> Dictionary:
	# The legacy no-item query retains its default; actual gear uses rarity caps.
	return {
		"max_level": 5 if item_id.is_empty() else GameState.roster_domain.gear_cap(item_id),
		"stat_bonus_per_level": 0.08,
		"currency": "gold",
		"material": "glade_sap",
		"gold_base": 180,
		"material_base": 1,
	}


static func upgrade_info(uid: String, slot: String) -> Dictionary:
	return GameState.roster_domain.gear_upgrade_info(uid, slot)


static func can_upgrade(uid: String, slot: String) -> bool:
	return bool(upgrade_info(uid, slot).get("ok", false))


static func apply_upgrade(uid: String, slot: String) -> bool:
	return GameState.roster_domain.enhance_gear(uid, slot)


static func validation_errors(uid: String, slot: String) -> Array[String]:
	var info := upgrade_info(uid, slot)
	if bool(info.get("ok", false)):
		return []
	return [str(info.get("reason", "Upgrade unavailable."))]
