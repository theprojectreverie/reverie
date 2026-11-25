extends Node

const DIALOGUE_SCENE := "res://scenes/ui/dialogue_box.tscn"
const NPC_DIALOGUES := ["castle_guard_west", "castle_guard_east", "wanderer_pip"]

func _ready() -> void:
	call_deferred("_run")

func _run() -> void:
	print("ROYAL GARDENS NPC DIALOGUE AUDIT: starting")
	var packed := load(DIALOGUE_SCENE) as PackedScene
	assert(packed != null, "Authored dialogue UI scene must load")
	var dialogue := packed.instantiate() as DialogueBox
	assert(dialogue != null, "Dialogue UI must instantiate")
	get_tree().root.add_child(dialogue)
	await get_tree().process_frame
	for dialogue_id in NPC_DIALOGUES:
		var data: Dictionary = ContentDB.get_dialogue(dialogue_id)
		assert(not data.is_empty(), "NPC dialogue data must exist: %s" % dialogue_id)
		var start_id := str(data.get("start", "greet"))
		var nodes: Dictionary = data.get("nodes", {})
		assert(nodes.has(start_id), "NPC dialogue start node must exist: %s" % dialogue_id)
		var start_node: Dictionary = nodes[start_id]
		assert(not str(start_node.get("speaker", "")).is_empty(), "NPC dialogue speaker must be authored")
		assert(not str(start_node.get("text", "")).is_empty(), "NPC dialogue text must be authored")
		dialogue.open(dialogue_id)
		assert(dialogue.visible, "Dialogue UI must open for %s" % dialogue_id)
		assert(dialogue._speaker_label.text == str(start_node.get("speaker", "")), "Dialogue UI speaker must match data for %s" % dialogue_id)
		assert(dialogue._text_label.text == str(start_node.get("text", "")), "Dialogue UI text must match data for %s" % dialogue_id)
		dialogue._finish_typing()
		var choices: Array = start_node.get("choices", [])
		assert(dialogue._choices_box.get_child_count() == choices.size(), "Dialogue UI must render all authored choices for %s" % dialogue_id)
		assert(dialogue._continue_button.visible == choices.is_empty(), "Continue button visibility must match choice availability")
		print("DIALOGUE OK: %s | speaker=%s | choices=%d" % [dialogue_id, dialogue._speaker_label.text, choices.size()])
		dialogue.close()
	print("ROYAL GARDENS NPC DIALOGUE AUDIT: PASS (3 data records render through production dialogue UI)")
	dialogue.queue_free()
	await get_tree().process_frame
	get_tree().quit(0)
