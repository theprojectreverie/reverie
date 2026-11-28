class_name GameRosterDomainComponent
extends Node
## Owns roster, party composition, character progression, bonds and equipment.

const PARTY_MAX := 4
const STARTING_CHARACTERS := ["gerald", "lilith", "kael"]
const MAX_PROFILE_LEVEL := 60

var roster: Array = []
var party: Array = []
const MAX_GEAR_LEVEL := 8
const GEAR_RARITY_CAPS := {"common": 3, "uncommon": 4, "rare": 5, "epic": 6, "legendary": 7, "mythic": 8}
var gear_levels: Dictionary = {}
var gear_rerolls: Dictionary = {}
# Enhanced copies in the bag; unmodified copies are represented by the remaining stack count.
var stored_gear: Dictionary = {}

var _uid_counter: int = 0


func reset_uid_counter() -> void:
	_uid_counter = 0


# ------------------------------------------------------------------- roster

func _make_uid() -> String:
	_uid_counter += 1
	return "c%d_%d" % [Time.get_ticks_usec(), _uid_counter]


func _find_instance(uid: String) -> CharacterInstance:
	for instance in roster:
		if instance.uid == uid:
			return instance
	return null


func owns_character(character_id: String) -> bool:
	for instance in roster:
		if instance.char_id == character_id:
			return true
	return false


## Grants any missing starting character directly (no duplicate/awakening
## bookkeeping) so new and migrated saves always own the full trio.
func _ensure_starting_characters() -> void:
	for character_id in STARTING_CHARACTERS:
		if owns_character(character_id):
			continue
		if ContentDB.get_character(character_id) == null:
			push_error("[GameState] Missing starting character definition: " + character_id)
			continue
		roster.append(CharacterInstance.create(character_id, _make_uid()))


## Replaces the party with the starting trio in canonical order.
func _reset_party_to_starters() -> void:
	party.clear()
	for character_id in STARTING_CHARACTERS:
		for instance in roster:
			if instance.char_id == character_id:
				party.append(instance.uid)
				break


func add_character(character_id: String) -> Dictionary:
	if ContentDB.get_character(character_id) == null:
		return { "is_new": false, "error": "unknown_character" }
	for instance in roster:
		if instance.char_id == character_id:
			instance.dupes += 1
			var gained := 0
			if instance.dupes >= 2 and instance.awakening < CharacterInstance.MAX_AWAKENING:
				instance.dupes -= 2
				instance.awakening += 1
				gained = 1
			EventBus.roster_changed.emit()
			GameState.queue_save()
			return { "instance": instance, "is_new": false, "awakening_gain": gained }
	var created := CharacterInstance.create(character_id, _make_uid())
	roster.append(created)
	if party.size() < PARTY_MAX:
		party.append(created.uid)
		EventBus.party_changed.emit()
	EventBus.roster_changed.emit()
	GameState.queue_save()
	return { "instance": created, "is_new": true, "awakening_gain": 0 }


## The opening story uses a temporary solo party, not a destructive roster reset.
func story_solo_active() -> bool:
	var scene := get_tree().current_scene
	if scene != null:
		if scene.name == &"StandaloneVillage":
			return not bool(GameState.quest_domain.flags.get("village_lilith_awakened", false))
		if scene.scene_file_path.begins_with("res://scenes/world/tutorial_prologue/"):
			return true
		if str(scene.name).begins_with("StandaloneZone"):
			return false
	var checkpoint: Dictionary = GameState.quest_domain.flags.get("six_zone_checkpoint", {})
	return str(checkpoint.get("zone", "")) == "StandaloneVillage" and not bool(GameState.quest_domain.flags.get("village_lilith_awakened", false))


func effective_party_ids() -> Array:
	if story_solo_active():
		var ids: Array = ["kael"]
		for id in ["crimson_witch_legendary", "nyx"]:
			if bool(GameState.quest_domain.flags.get("village_recruited_" + id, false)):
				ids.append(id)
		var selected: Array = []
		for id in ids:
			for instance in roster:
				if instance.char_id == id:
					selected.append(instance.uid)
					break
		return selected
	return party.duplicate()


## Runtime account projection only; never writes into the legacy local save.
func account_instances() -> Array:
	var result: Array = []
	if not AuthGateway.is_authenticated():
		return result
	for row in AuthGateway.account_roster.get("roster", []):
		var id := str(row.get("char_id", ""))
		if ContentDB.get_character(id) == null:
			continue
		var data: Dictionary = row.duplicate(true)
		data["uid"] = "account:" + id
		data["equipment"] = {}
		for gear in row.get("equipment", []):
			data.equipment[str(gear.slot)] = str(gear.item_id)
		result.append(CharacterInstance.from_dict(data))
	return result


func account_gear(uid: String, slot: String) -> Dictionary:
	if not uid.begins_with("account:"):
		return {}
	for row in AuthGateway.account_roster.get("roster", []):
		if "account:" + str(row.char_id) != uid:
			continue
		for gear in row.get("equipment", []):
			if str(gear.slot) == slot:
				return gear
	return {}


func gameplay_instance(uid: String) -> CharacterInstance:
	if uid.begins_with("account:"):
		for instance in account_instances():
			if instance.uid == uid:
				return instance
		return null
	return _find_instance(uid)


func party_instances() -> Array:
	if AuthGateway.is_authenticated():
		var result: Array = []
		var ids: Array = ["kael"] if story_solo_active() else AuthGateway.account_roster.get("party", [])
		var zone := get_tree().current_scene
		if story_solo_active() and zone != null and zone.has_node("StoryVillageProgressionSync"):
			ids = zone.get_node("StoryVillageProgressionSync").party_ids()
		var local_village: bool = story_solo_active() and zone != null and zone.name == &"StandaloneVillage" and preload("res://scripts/online/connection_profile.gd").is_public_alpha() and not zone.has_node("StoryVillageProgressionSync") and MultiplayerGateway.standalone_expedition_id.is_empty()
		if local_village:
			for guest in ["crimson_witch_legendary", "nyx"]:
				if bool(GameState.quest_domain.flags.get("village_recruited_" + guest, false)):
					ids.append(guest)
		var owned := account_instances()
		for id in ids:
			for instance in owned:
				if instance.char_id == id:
					result.append(instance)
					break
			if local_village and id != "kael" and not result.any(func(entry): return entry.char_id == id):
				# Chapter-only ally; not inserted into account roster or saved ownership.
				result.append(CharacterInstance.create(id, "story_guest:" + id))
		return result
	return local_party_instances()


func local_party_instances() -> Array:
	var result: Array = []
	for uid in effective_party_ids():
		var instance := _find_instance(uid)
		if instance != null:
			result.append(instance)
	return result


func set_party(uids: Array) -> bool:
	if story_solo_active():
		EventBus.toast_requested.emit("The story determines your active party during this chapter.")
		return false
	var cleaned: Array = []
	for uid in uids:
		var text := str(uid)
		if _find_instance(text) != null and not cleaned.has(text) and cleaned.size() < PARTY_MAX:
			cleaned.append(text)
	if cleaned.is_empty():
		return false
	party = cleaned
	EventBus.party_changed.emit()
	GameState.queue_save()
	return true


func _fill_party() -> void:
	for instance in roster:
		if party.size() >= PARTY_MAX:
			break
		if not party.has(instance.uid):
			party.append(instance.uid)


func unique_owned_count() -> int:
	var ids: Dictionary = {}
	for instance in roster:
		ids[instance.char_id] = true
	return ids.size()


func collection_bonus() -> float:
	return 1.0 + minf(0.15, 0.01 * floori(unique_owned_count() / 3.0))


func xp_to_next(level: int) -> int:
	return 100 + (level - 1) * 85


func add_xp_to_character(instance: CharacterInstance, amount: int) -> Dictionary:
	if instance == null or amount <= 0:
		return { "levels": 0 }
	var levels_gained := 0
	instance.xp += amount
	while not instance.is_max_level() and instance.xp >= xp_to_next(instance.level):
		instance.xp -= xp_to_next(instance.level)
		instance.level += 1
		levels_gained += 1
	if instance.is_max_level():
		instance.xp = 0
	EventBus.roster_changed.emit()
	GameState.queue_save()
	if levels_gained > 0:
		AudioDirector.play_variant("level_up")
	return { "levels": levels_gained }


func add_party_xp(amount: int) -> void:
	# Legacy story awards remain isolated until server-owned combat settlement.
	for instance in local_party_instances():
		add_xp_to_character(instance, amount)
	add_profile_xp(amount / 2)


func add_profile_xp(amount: int) -> void:
	GameState.profile_domain.add_xp(amount)

func ascension_info(uid: String) -> Dictionary:
	var instance := _find_instance(uid)
	if instance == null:
		return { "ok": false, "reason": "Character not found." }
	if instance.ascension >= CharacterInstance.MAX_ASCENSION:
		return { "ok": false, "reason": "Already fully ascended." }
	if not instance.is_max_level():
		return { "ok": false, "reason": "Reach level %d first." % instance.level_cap() }
	var gold_cost := 800 * (instance.ascension + 1)
	var dew_cost := instance.ascension + 1
	if GameState.inventory_domain.currency("gold") < gold_cost:
		return { "ok": false, "reason": "Need %d gold." % gold_cost }
	if GameState.inventory_domain.item_count("dew_of_awakening") < dew_cost:
		return { "ok": false, "reason": "Need %d Dew of Awakening." % dew_cost }
	return { "ok": true, "gold": gold_cost, "dew": dew_cost }


func ascend(uid: String) -> bool:
	var info := ascension_info(uid)
	if not bool(info.get("ok", false)):
		return false
	var instance := _find_instance(uid)
	if instance == null:
		return false
	if not GameState.inventory_domain.spend_currency("gold", int(info.gold)):
		return false
	if not GameState.inventory_domain.remove_item("dew_of_awakening", int(info.dew)):
		GameState.inventory_domain.add_currency("gold", int(info.gold))
		return false
	instance.ascension += 1
	instance.level += 1
	EventBus.roster_changed.emit()
	GameState.queue_save()
	return true


func awakening_info(uid: String) -> Dictionary:
	var instance := _find_instance(uid)
	if instance == null:
		return { "ok": false, "reason": "Character not found." }
	if instance.awakening >= CharacterInstance.MAX_AWAKENING:
		return { "ok": false, "reason": "Already fully awakened." }
	if instance.dupes < 2:
		return { "ok": false, "reason": "Need 2 duplicate copies (have %d)." % instance.dupes }
	return { "ok": true, "dupes_needed": 2, "current": instance.awakening, "next": instance.awakening + 1 }


func awaken(uid: String) -> bool:
	var info := awakening_info(uid)
	if not bool(info.get("ok", false)):
		return false
	var instance := _find_instance(uid)
	if instance == null:
		return false
	instance.dupes -= int(info.dupes_needed)
	instance.awakening += 1
	EventBus.roster_changed.emit()
	GameState.queue_save()
	return true


func add_bond(uid: String, amount: int) -> void:
	if amount <= 0:
		return
	var instance := _find_instance(uid)
	if instance == null:
		return
	instance.bond = mini(instance.bond + amount, 100)
	EventBus.roster_changed.emit()
	GameState.queue_save()


func bond_level(uid: String) -> int:
	var instance := gameplay_instance(uid)
	if instance == null:
		return 0
	return int(instance.bond / 10)


func bond_bonus_atk(uid: String) -> float:
	return float(bond_level(uid)) * 0.02



func skill_upgrade_info(uid: String, skill_id: String) -> Dictionary:
	var instance := _find_instance(uid)
	if instance == null:
		return {"ok": false, "reason": "Character not found."}
	var definition := ContentDB.get_character(instance.char_id)
	var skill := ContentDB.get_skill(skill_id)
	if definition == null or skill == null or skill_id.is_empty() or (skill_id not in definition.skills and skill_id != definition.ultimate):
		return {"ok": false, "reason": "This character does not know this skill."}
	if skill.kind not in ["damage", "heal", "shield", "buff", "debuff"]:
		return {"ok": false, "reason": "This skill cannot be upgraded."}
	var level := instance.skill_level(skill_id)
	if level >= CharacterInstance.MAX_SKILL_LEVEL:
		return {"ok": false, "reason": "Maximum skill level."}
	var gold := (150 if skill.ultimate else 100) * level
	var petals := level
	var required_level := level * 5
	var info := {"ok": true, "next": level + 1, "gold": gold, "petals": petals, "required_level": required_level, "reason": ""}
	if instance.level < required_level:
		info.ok = false
		info.reason = "Requires character level %d." % required_level
	elif GameState.inventory_domain.currency("gold") < gold:
		info.ok = false
		info.reason = "Not enough gold."
	elif GameState.inventory_domain.item_count("moonpetal") < petals:
		info.ok = false
		info.reason = "Not enough Moonpetal."
	return info


func upgrade_skill(uid: String, skill_id: String) -> bool:
	if not MultiplayerGateway.standalone_expedition_id.is_empty():
		return false
	var info := skill_upgrade_info(uid, skill_id)
	if not bool(info.get("ok", false)):
		return false
	var instance := _find_instance(uid)
	if not GameState.inventory_domain.spend_currency("gold", int(info.gold)):
		return false
	if not GameState.inventory_domain.remove_item("moonpetal", int(info.petals)):
		GameState.inventory_domain.add_currency("gold", int(info.gold))
		return false
	instance.skill_levels[skill_id] = int(info.next)
	EventBus.roster_changed.emit()
	GameState.queue_save()
	return true


func stored_copies(item_id: String) -> Array:
	var copies: Variant = stored_gear.get(item_id, [])
	return copies if copies is Array else []

func best_stored_gear(item_id: String) -> Dictionary:
	var copies := stored_copies(item_id)
	return copies[0].duplicate(true) if not copies.is_empty() else {}

func _store_equipped_gear(instance: CharacterInstance, slot: String) -> void:
	var item_id := instance.equipped_item(slot)
	var key := instance.uid + "|" + slot
	var level := gear_level(instance.uid, slot)
	var roll: Dictionary = gear_rerolls.get(key, {}).duplicate(true)
	if not item_id.is_empty() and (level > 0 or not roll.is_empty()):
		var copies := stored_copies(item_id)
		copies.append({"level": level, "reroll": roll})
		copies.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
			return int(a.get("level", 0)) > int(b.get("level", 0)) or (int(a.get("level", 0)) == int(b.get("level", 0)) and not a.get("reroll", {}).is_empty() and b.get("reroll", {}).is_empty())
		)
		stored_gear[item_id] = copies
	gear_levels.erase(key)
	gear_rerolls.erase(key)

func _take_stored_gear(item_id: String) -> Dictionary:
	var copies := stored_copies(item_id)
	if copies.is_empty():
		return {}
	var record: Dictionary = copies.pop_front()
	if copies.is_empty():
		stored_gear.erase(item_id)
	return record

func restore_stored_gear(saved: Variant) -> void:
	stored_gear = {}
	if not saved is Dictionary:
		return
	for id in saved:
		var item_id := str(id)
		if str(ContentDB.get_item(item_id).get("category", "")) != "equipment" or not saved[id] is Array:
			continue
		var copies: Array = []
		for record in saved[id]:
			if copies.size() >= GameState.inventory_domain.item_count(item_id):
				break
			if not record is Dictionary:
				continue
			var level := clampi(int(record.get("level", 0)), 0, MAX_GEAR_LEVEL)
			var roll: Variant = record.get("reroll", {})
			var checked_roll: Dictionary = roll.duplicate(true) if roll is Dictionary else {}
			if level > 0 or not checked_roll.is_empty():
				copies.append({"level": level, "reroll": checked_roll})
		if not copies.is_empty():
			copies.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return int(a.level) > int(b.level))
			stored_gear[item_id] = copies

func equip_item(uid: String, item_id: String) -> bool:
	var instance := _find_instance(uid)
	if instance == null:
		return false
	var item: Dictionary = ContentDB.get_item(item_id)
	if str(item.get("category", "")) != "equipment":
		return false
	var slot := str(item.get("slot", ""))
	if not CharacterInstance.SLOTS.has(slot):
		return false
	if GameState.inventory_domain.item_count(item_id) <= 0:
		return false
	var previous := instance.equipped_item(slot)
	if previous == item_id:
		return false
	var record := _take_stored_gear(item_id)
	var bag: Dictionary = GameState.inventory_domain.inventory
	var remaining := int(bag.get(item_id, 0)) - 1
	if remaining == 0:
		bag.erase(item_id)
	else:
		bag[item_id] = remaining
	if not previous.is_empty():
		_store_equipped_gear(instance, slot)
		bag[previous] = int(bag.get(previous, 0)) + 1
	else:
		gear_levels.erase(uid + "|" + slot)
		gear_rerolls.erase(uid + "|" + slot)
	instance.equip(item_id, slot)
	var key := uid + "|" + slot
	if int(record.get("level", 0)) > 0:
		gear_levels[key] = int(record.level)
	var roll: Dictionary = record.get("reroll", {})
	if not roll.is_empty():
		gear_rerolls[key] = roll.duplicate(true)
	EventBus.inventory_changed.emit()
	EventBus.roster_changed.emit()
	GameState.queue_save()
	return true


func unequip_item(uid: String, slot: String) -> bool:
	var instance := _find_instance(uid)
	if instance == null:
		return false
	var current := instance.equipped_item(slot)
	if current.is_empty():
		return false
	_store_equipped_gear(instance, slot)
	instance.unequip(slot)
	GameState.inventory_domain.add_item(current, 1)
	EventBus.roster_changed.emit()
	GameState.queue_save()
	return true


func gear_reroll_info(uid: String, slot: String) -> Dictionary:
	var instance := _find_instance(uid)
	if instance == null or not CharacterInstance.SLOTS.has(slot):
		return {"ok": false, "reason": "Invalid character or equipment slot."}
	var item_id := instance.equipped_item(slot)
	if item_id.is_empty():
		return {"ok": false, "reason": "Equip an item in this slot first."}
	var stats: Dictionary = ContentDB.get_item(item_id).get("stats", {})
	var candidates: Array[String] = []
	for stat in ["hp", "atk", "def", "spd", "crit", "crit_dmg"]:
		if float(stats.get(stat, 0.0)) > 0.0:
			candidates.append(stat)
	if candidates.is_empty():
		return {"ok": false, "reason": "This equipment has no rerollable stats."}
	if GameState.inventory_domain.currency("gold") < 120:
		return {"ok": false, "reason": "Need 120 gold."}
	if GameState.inventory_domain.item_count("gothic_shard") < 1:
		return {"ok": false, "reason": "Need 1 Gothic Shard."}
	return {"ok": true, "gold": 120, "shards": 1, "item_id": item_id, "candidates": candidates}


func reroll_gear(uid: String, slot: String) -> Dictionary:
	var info := gear_reroll_info(uid, slot)
	if not bool(info.get("ok", false)):
		return {"ok": false, "reason": str(info.get("reason", "Cannot reroll this equipment."))}
	var key := uid + "|" + slot
	var old_roll: Dictionary = gear_rerolls.get(key, {})
	var candidates: Array = info.get("candidates", [])
	if candidates.size() > 1 and not old_roll.is_empty():
		var previous_stat := str(old_roll.get("stat", ""))
		var alternatives: Array = candidates.filter(func(stat): return str(stat) != previous_stat)
		if not alternatives.is_empty():
			candidates = alternatives
	var chosen := str(candidates[randi_range(0, candidates.size() - 1)])
	var base_stats: Dictionary = ContentDB.get_item(str(info.item_id)).get("stats", {})
	var minimum := 0.001 if chosen in ["crit", "crit_dmg"] else 1.0
	var amount := maxf(minimum, float(base_stats.get(chosen, 0.0)) * 0.10)
	if not GameState.inventory_domain.spend_currency("gold", int(info.gold)):
		return {"ok": false, "reason": "Gold balance changed; reroll cancelled."}
	if not GameState.inventory_domain.remove_item("gothic_shard", int(info.shards)):
		GameState.inventory_domain.add_currency("gold", int(info.gold))
		return {"ok": false, "reason": "Gothic Shard unavailable; gold returned."}
	gear_rerolls[key] = {"stat": chosen, "value": amount, "item_id": str(info.item_id)}
	EventBus.roster_changed.emit()
	GameState.queue_save()
	return {"ok": true, "stat": chosen, "value": amount, "previous": old_roll.duplicate(true)}


func gear_level(uid: String, slot: String) -> int:
	if uid.begins_with("account:"):
		return clampi(int(account_gear(uid, slot).get("enhancement_level", 0)), 0, MAX_GEAR_LEVEL)
	return clampi(int(gear_levels.get(uid + "|" + slot, 0)), 0, MAX_GEAR_LEVEL)


func gear_cap(item_id: String) -> int:
	var rarity := str(ContentDB.get_item(item_id).get("rarity", "common"))
	return int(GEAR_RARITY_CAPS.get(rarity, 5))


func gear_upgrade_info(uid: String, slot: String) -> Dictionary:
	var instance := _find_instance(uid)
	if instance == null or not CharacterInstance.SLOTS.has(slot):
		return { "ok": false, "reason": "Invalid character or equipment slot." }
	var item_id := instance.equipped_item(slot)
	if item_id.is_empty():
		return { "ok": false, "reason": "Equip an item in this slot first." }
	var level := gear_level(uid, slot)
	var cap := gear_cap(item_id)
	if level >= cap:
		return {"ok": false, "level": level, "cap": cap, "reason": "This item is fully enhanced."}
	var gold_cost := 180 * (level + 1)
	var sap_cost := level + 1
	var shards := maxi(0, level - 4)
	var info := {"ok": true, "level": level, "cap": cap, "next": level + 1, "gold": gold_cost, "sap": sap_cost, "shards": shards, "item_id": item_id, "reason": ""}
	if GameState.inventory_domain.currency("gold") < gold_cost:
		info.ok = false
		info.reason = "Need %d gold." % gold_cost
	elif GameState.inventory_domain.item_count("glade_sap") < sap_cost:
		info.ok = false
		info.reason = "Need %d Glade Sap." % sap_cost
	elif GameState.inventory_domain.item_count("gothic_shard") < shards:
		info.ok = false
		info.reason = "Need %d Gothic Shard." % shards
	return info


func enhance_gear(uid: String, slot: String) -> bool:
	var info := gear_upgrade_info(uid, slot)
	if not bool(info.get("ok", false)):
		return false
	if not GameState.inventory_domain.spend_currency("gold", int(info.gold)):
		return false
	if not GameState.inventory_domain.remove_item("glade_sap", int(info.sap)):
		GameState.inventory_domain.add_currency("gold", int(info.gold))
		return false
	if int(info.shards) > 0 and not GameState.inventory_domain.remove_item("gothic_shard", int(info.shards)):
		GameState.inventory_domain.add_item("glade_sap", int(info.sap))
		GameState.inventory_domain.add_currency("gold", int(info.gold))
		return false
	gear_levels[uid + "|" + slot] = int(info.next)
	EventBus.roster_changed.emit()
	GameState.queue_save()
	return true




# Keep the opening roster intact, but deploy only Kael and earned village allies.
func deploy_village_recruits() -> void:
	if AuthGateway.is_authenticated():
		return
	var selected: Array = []
	for id in ["kael", "crimson_witch_legendary", "nyx"]:
		if id != "kael" and not bool(GameState.quest_domain.flags.get("village_recruited_" + id, false)):
			continue
		for instance in roster:
			if instance.char_id == id:
				selected.append(instance.uid)
				break
	if not selected.is_empty():
		party = selected
		EventBus.party_changed.emit()
		GameState.queue_save()
