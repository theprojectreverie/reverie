extends Node

func _ready() -> void:
	call_deferred("run")

func fail(message: String) -> void:
	push_error(message)
	get_tree().quit(1)

func run() -> void:
	var box: DialogueBox = load("res://scenes/ui/dialogue_box.tscn").instantiate()
	add_child(box)
	await get_tree().process_frame
	var count := 0
	for id in ContentDB.dialogues:
		var data: Dictionary = ContentDB.get_dialogue(id)
		for node_id in data.get("nodes", {}):
			var line: Dictionary = data.nodes[node_id]
			var speaker := str(line.get("speaker", "")).strip_edges().to_lower()
			var explicit := str(line.get("portrait_asset", ""))
			if not DialogueBox.STORY_PORTRAITS.has(speaker) and explicit.is_empty():continue
			box._dialogue_id = id
			box._data = data
			box._show_node(node_id)
			var expected := load(explicit) as Texture2D if not explicit.is_empty() else DialogueBox.STORY_PORTRAITS.get(speaker) as Texture2D
			if expected == null or box._portrait.portrait_texture != expected or not box._portrait.portrait_art.visible:
				fail("Portrait mismatch: "+id+"/"+node_id+" "+speaker);return
			count+=1
	box.open("revienna_challenge")
	box._show_node("reply")
	if box._portrait.portrait_texture.resource_path != "res://assets/characters/kael_avatar/dialogue_portrait.tres":
		fail("Ruined Tower Kael portrait incorrect");return
	box._node.erase("portrait_asset")
	box._show_node("reply")
	if box._portrait.portrait_texture.resource_path != "res://assets/characters/kael_avatar/dialogue_portrait.tres":
		fail("Kael fallback incorrect");return
	print("PASS ",count," authored dialogue portraits, Ruined Tower Kael, and named fallback")
	box.queue_free()
	await get_tree().process_frame
	get_tree().quit()