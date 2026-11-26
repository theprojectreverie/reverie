extends Node
func _ready() -> void:
	var selector = preload("res://scripts/ui/components/menu_character_selector.gd")
	assert(selector.LABELS["elathra"] == "Companion")
	assert(selector.LABELS["crimson_witch"] == "Elathra")
	assert(selector.ART["crimson_witch"].ends_with("05_lily_witch.png"))
	assert(selector.ART["elathra"].ends_with("06_elathra.png"))
	assert(ContentDB.get_character("elathra").display_name == "Elathra")
	var definitions = JSON.parse_string(FileAccess.get_file_as_string("res://resources/data/characters.json"))
	assert(definitions.crimson_witch.name == "Crimson Witch")
	var dialogue = JSON.parse_string(FileAccess.get_file_as_string("res://resources/data/dialogue.json"))
	for node in dialogue.elathra.nodes.values():
		assert(node.speaker == "Elathra")
	var quests = JSON.parse_string(FileAccess.get_file_as_string("res://resources/data/quests.json"))
	assert(quests.elathra_first_audience.summary.contains("Elathra"))
	assert(quests.elathra_first_audience.steps[0].target == "elathra")
	print("PASS both menu appearance names, correct character names, dialogue and preserved IDs")
	get_tree().quit(0)