class_name CraftingService
extends RefCounted
## Offline, deterministic crafting recipes. GameState remains authoritative.

const RECIPES: Dictionary = {
	"wayfarer_charm": {
		"name": "Wayfarer Charm",
		"description": "Carve a traveler's charm from living wood and moonpetal.",
		"materials": {"glade_sap": 2, "moonpetal": 1},
		"gold": 150,
		"output": {"wayfarer_charm": 1}
	},
	"mossweave_vest": {
		"name": "Mossweave Vest",
		"description": "Weave a protective vest from gathered Greenward materials.",
		"materials": {"glade_sap": 3, "moonpetal": 2},
		"gold": 250,
		"output": {"mossweave_vest": 1}
	},
	"gladewood_bow": {
		"name": "Gladewood Bow",
		"description": "Shape a living bow from sap, moonpetals and a royal seal.",
		"materials": {"glade_sap": 5, "moonpetal": 3, "royal_seal": 1},
		"gold": 400,
		"output": {"gladewood_bow": 1}
	},
	"awakening_dew": {
		"name": "Dew of Awakening",
		"description": "Distill awakening dew from moonpetals, sap and a Gothic Shard.",
		"materials": {"moonpetal": 3, "glade_sap": 2, "gothic_shard": 1},
		"gold": 300,
		"output": {"dew_of_awakening": 1}
	},
	"sunfire_royal_forge": {
		"name": "Sunfire Blade - Royal Forge",
		"description": "Forge the legendary blade from a royal seal, Gothic Shards and awakening dew.",
		"materials": {"royal_seal": 1, "gothic_shard": 4, "dew_of_awakening": 2},
		"gold": 700,
		"output": {"sunfire_blade": 1}
	},
	"sunfire_blade": {
		"name": "Sunfire Blade",
		"description": "Temper a legendary blade around a Hollow Heart and awakening dew.",
		"materials": {"hollow_heart": 1, "dew_of_awakening": 2},
		"gold": 500,
		"output": {"sunfire_blade": 1}
	}
}


static func recipe_ids() -> Array[String]:
	var result: Array[String] = []
	for key in RECIPES.keys():
		result.append(str(key))
	result.sort()
	return result


static func get_recipe(recipe_id: String) -> Dictionary:
	return (RECIPES.get(recipe_id, {}) as Dictionary).duplicate(true)


static func recipe_status(recipe_id: String) -> Dictionary:
	var recipe := get_recipe(recipe_id)
	if recipe.is_empty():
		return {"ok": false, "reason": "Unknown recipe."}
	var output: Dictionary = recipe.get("output", {})
	if output.is_empty():
		return {"ok": false, "reason": "Recipe has no output."}
	for item_id in output:
		if ContentDB.get_item(str(item_id)).is_empty() or int(output[item_id]) <= 0:
			return {"ok": false, "reason": "Recipe output is invalid."}
	var materials: Dictionary = recipe.get("materials", {})
	for item_id in materials:
		if ContentDB.get_item(str(item_id)).is_empty() or ItemDatabase.is_currency(str(item_id)) or int(materials[item_id]) <= 0:
			return {"ok": false, "reason": "Recipe material cost is invalid."}
	var gold_cost := int(recipe.get("gold", 0))
	if gold_cost < 0:
		return {"ok": false, "reason": "Recipe gold cost is invalid."}
	var missing: Dictionary = {}
	for item_id in materials:
		var required := int(materials[item_id])
		var owned := GameState.inventory_domain.item_count(str(item_id))
		if owned < required:
			missing[str(item_id)] = {"required": required, "owned": owned}
	if GameState.inventory_domain.currency("gold") < gold_cost:
		missing["gold"] = {"required": gold_cost, "owned": GameState.inventory_domain.currency("gold")}
	return {
		"ok": missing.is_empty(),
		"craftable": missing.is_empty(),
		"missing": missing,
		"recipe": recipe
	}


static func craft(recipe_id: String) -> Dictionary:
	var status := recipe_status(recipe_id)
	if not bool(status.get("ok", false)):
		return {"ok": false, "reason": str(status.get("reason", "Missing crafting materials.")), "missing": status.get("missing", {})}
	var recipe: Dictionary = status["recipe"]
	# Roll back earlier deductions if any material changes during callbacks.
	var consumed: Dictionary = {}
	for item_id in recipe["materials"]:
		if not GameState.inventory_domain.remove_item(str(item_id), int(recipe["materials"][item_id])):
			for restored in consumed:
				GameState.inventory_domain.add_item(str(restored), int(consumed[restored]))
			return {"ok": false, "reason": "Material inventory changed; nothing was crafted."}
		consumed[item_id] = int(recipe["materials"][item_id])
	if not GameState.inventory_domain.spend_currency("gold", int(recipe.get("gold", 0))):
		# Defensive rollback in case wallet state changed between validation and charge.
		for item_id in recipe["materials"]:
			GameState.inventory_domain.add_item(str(item_id), int(recipe["materials"][item_id]))
		return {"ok": false, "reason": "Gold balance changed; materials were returned."}
	GameState.inventory_domain.grant_reward_items(recipe["output"])
	return {"ok": true, "output": recipe["output"].duplicate(true), "recipe_id": recipe_id, "reason": "Crafted %s." % str(recipe.get("name", recipe_id))}
