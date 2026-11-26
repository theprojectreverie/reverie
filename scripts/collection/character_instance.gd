class_name CharacterInstance
extends RefCounted
## A player-owned copy of a character: progression, duplicates and equipment.
## Definitions are immutable (CharacterDef); instances are saved.

const LEVEL_CAP_PER_ASCENSION := 20
const MAX_ASCENSION := 3
const MAX_AWAKENING := 5
const MAX_SKILL_LEVEL := 5
const SLOTS := ["weapon", "armor", "accessory"]

var uid: String = ""
var char_id: String = ""
var level: int = 1
var xp: int = 0
var ascension: int = 0
var awakening: int = 0
var bond: int = 0
var dupes: int = 0
var equipment: Dictionary = {}
var skill_levels: Dictionary = {}


static func create(character_id: String, instance_uid: String) -> CharacterInstance:
	var instance := CharacterInstance.new()
	instance.uid = instance_uid
	instance.char_id = character_id
	return instance


static func from_dict(data: Dictionary) -> CharacterInstance:
	var instance := CharacterInstance.new()
	instance.uid = str(data.get("uid", ""))
	instance.char_id = str(data.get("char_id", ""))
	instance.level = maxi(1, int(data.get("level", 1)))
	instance.xp = maxi(0, int(data.get("xp", 0)))
	instance.ascension = clampi(int(data.get("ascension", 0)), 0, MAX_ASCENSION)
	instance.awakening = clampi(int(data.get("awakening", 0)), 0, MAX_AWAKENING)
	instance.bond = maxi(0, int(data.get("bond", 0)))
	instance.dupes = maxi(0, int(data.get("dupes", 0)))
	instance.equipment = data.get("equipment", {})
	var saved: Variant = data.get("skill_levels", {})
	if saved is Dictionary:
		for id in saved:
			if saved[id] is int or saved[id] is float:
				instance.skill_levels[str(id)] = clampi(int(saved[id]), 1, MAX_SKILL_LEVEL)
	return instance


func to_dict() -> Dictionary:
	return {
		"uid": uid,
		"char_id": char_id,
		"level": level,
		"xp": xp,
		"ascension": ascension,
		"awakening": awakening,
		"bond": bond,
		"dupes": dupes,
		"equipment": equipment,
		"skill_levels": skill_levels.duplicate(true),
	}


func skill_level(skill_id: String) -> int:
	return clampi(int(skill_levels.get(skill_id, 1)), 1, MAX_SKILL_LEVEL)


func level_cap() -> int:
	return LEVEL_CAP_PER_ASCENSION * (ascension + 1)


func is_max_level() -> bool:
	return level >= level_cap()


func power_multiplier() -> float:
	return (1.0 + 0.085 * (level - 1)) \
		* (1.0 + 0.10 * ascension) \
		* (1.0 + 0.04 * awakening)


func equipped_item(slot: String) -> String:
	return str(equipment.get(slot, ""))


func equip(item_id: String, slot: String) -> void:
	equipment[slot] = item_id


func unequip(slot: String) -> void:
	equipment.erase(slot)
