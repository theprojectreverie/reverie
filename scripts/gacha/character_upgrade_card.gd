extends RefCounted

static func definition(id: String) -> Dictionary:
	for banner in ContentDB.banners.values():
		var card: Dictionary = banner.get("upgrade_cards", {}).get(id, {})
		if not card.is_empty():
			return card
	return {}

static func grant(id: String) -> Array:
	var card := definition(id)
	if card.is_empty():
		return []
	GameState.inventory_domain.add_item(id, 1)
	var fusions: Array = []
	var current := id
	# Rare and Epic cards produce the matching Legendary; Mythic progress is tracked separately.
	for step in range(2):
		card = definition(current)
		if card.is_empty():
			break
		var cost := int(card.cost)
		var target := str(card.target)
		while GameState.inventory_domain.item_count(current) >= cost:
			if not GameState.inventory_domain.remove_item(current, cost):
				break
			if not definition(target).is_empty():
				GameState.inventory_domain.add_item(target, 1)
				fusions.append({"id":target, "name":str(ContentDB.get_item(target).get("name", target))})
			else:
				var result: Dictionary = GameState.roster_domain.add_character(target)
				fusions.append({"id":target,"name":ContentDB.get_character(target).display_name,"is_new":bool(result.get("is_new", false))})
				fusions.append_array(record_legendary(target))
		if not fusions.any(func(f): return f.id == target):
			break
		current = target
	return fusions

static func status(roll: Dictionary) -> String:
	var card := definition(str(roll.character_id))
	if card.is_empty():
		return ""
	var fusions: Array = roll.get("fusions", [])
	if not fusions.is_empty():
		return "Fused: " + str(fusions.back().get("name", ""))
	return "%d / %d cards" % [int(roll.get("card_count", 0)), int(card.cost)] if roll.has("card_count") else "Collect %d matching cards" % int(card.cost)


static func mythic_recipe(id: String) -> Dictionary:
	for banner in ContentDB.banners.values():
		var recipe: Dictionary = banner.get("mythic_fusion", {}).get(id, {})
		if not recipe.is_empty():
			return recipe
	return {}

static func record_legendary(id: String) -> Array:
	var recipe := mythic_recipe(id)
	if recipe.is_empty():
		return []
	var item := str(recipe.item)
	var cost := int(recipe.cost)
	var target := str(recipe.target)
	GameState.inventory_domain.add_item(item, 1)
	var fusions: Array = []
	while GameState.inventory_domain.item_count(item) >= cost:
		if not GameState.inventory_domain.remove_item(item, cost):
			break
		var added: Dictionary = GameState.roster_domain.add_character(target)
		fusions.append({"id":target,"name":ContentDB.get_character(target).display_name,"is_new":bool(added.get("is_new", false))})
		fusions.append_array(record_mythic(target))
	return fusions


static func ascension_recipe(id: String) -> Dictionary:
	for banner in ContentDB.banners.values():
		var recipe: Dictionary = banner.get("mythic_ascension", {}).get(id, {})
		if not recipe.is_empty():
			return recipe
	return {}

static func record_mythic(id: String) -> Array:
	var recipe := ascension_recipe(id)
	if recipe.is_empty():
		return []
	var item := str(recipe.item)
	var cost := int(recipe.cost)
	var count: int = GameState.inventory_domain.item_count(item)
	if count >= cost:
		return []
	for instance in GameState.roster_domain.roster:
		if instance.char_id != id:
			continue
		GameState.inventory_domain.add_item(item, 1)
		if count + 1 >= cost:
			instance.ascension = CharacterInstance.MAX_ASCENSION
			EventBus.roster_changed.emit()
			GameState.queue_save()
			return [{"id":id, "name":ContentDB.get_character(id).display_name + " - Fully Ascended", "fully_ascended":true}]
		return []
	return []

static func bonds() -> Array:
	for banner in ContentDB.banners.values():
		if banner.has("ascended_bonds"):
			return banner.ascended_bonds
	return []

static func active_bonds(party: Array) -> Array:
	var ids: Array = []
	for instance in party:
		if instance.ascension == CharacterInstance.MAX_ASCENSION:
			ids.append(instance.char_id)
	var active: Array = []
	for bond in bonds():
		if ids.has(bond.members[0]) and ids.has(bond.members[1]):
			active.append(bond)
	return active
