extends Node
const DIALOGUE_SCENE := "res://scenes/ui/dialogue_box.tscn"
const DIALOGUE_IDS := ["castle_guard_west", "castle_guard_east", "wanderer_pip"]

func _ready() -> void:
	call_deferred("_run")

func _run() -> void:
	print("ROYAL GARDENS NPC DIALOGUE TRANSITIONS: starting")
	var packed := load(DIALOGUE_SCENE) as PackedScene
	assert(packed != null)
	var dialogue := packed.instantiate() as DialogueBox
	assert(dialogue != null)
	get_tree().root.add_child(dialogue)
	await get_tree().process_frame
	for dialogue_id in DIALOGUE_IDS:
		var data: Dictionary = ContentDB.get_dialogue(dialogue_id)
		var nodes: Dictionary = data.get("nodes", {})
		assert(nodes.has(str(data.get("start", "greet"))))
		for node_id in nodes:
			var node: Dictionary = nodes[node_id]
			var next := str(node.get("next", ""))
			if not next.is_empty():
				assert(nodes.has(next), "%s.%s missing %s" % [dialogue_id, node_id, next])
			for choice in node.get("choices", []):
				var target := str(choice.get("next", ""))
				if not target.is_empty():
					assert(nodes.has(target), "%s.%s choice missing %s" % [dialogue_id, node_id, target])
		print("DIALOGUE GRAPH OK: %s | %d nodes" % [dialogue_id, nodes.size()])

	var previous_quests: Dictionary = GameState.quest_domain.quests.duplicate(true)
	var previous_flags: Dictionary = GameState.quest_domain.flags.duplicate(true)
	GameState.quest_domain.quests.erase("pip_whispers")
	GameState.quest_domain.flags.erase("tracked_quest")
	var pip: Dictionary = ContentDB.get_dialogue("wanderer_pip")
	var nodes: Dictionary = pip.get("nodes", {})
	dialogue.open("wanderer_pip")
	dialogue._finish_typing()
	assert(dialogue._choices_box.get_child_count() == 3)
	(dialogue._choices_box.get_child(0) as Button).pressed.emit()
	assert(dialogue.visible and dialogue._node_id == "lore")
	dialogue._finish_typing()
	assert(dialogue._choices_box.get_child_count() == 0 and dialogue._continue_button.visible)
	dialogue._continue_button.pressed.emit()
	assert(not dialogue.visible)
	print("PIP LORE BRANCH: PASS (choice -> lore -> close)")

	# Execute the real dialogue action, not just inspect its JSON link.
	dialogue.open("wanderer_pip")
	dialogue._finish_typing()
	(dialogue._choices_box.get_child(1) as Button).pressed.emit()
	assert(dialogue.visible and dialogue._node_id == "whispers_intro")
	dialogue._finish_typing()
	assert(dialogue._choices_box.get_child_count() == 2)
	(dialogue._choices_box.get_child(0) as Button).pressed.emit()
	assert(dialogue.visible and dialogue._node_id == "whispers_accepted")
	assert(GameState.quest_domain.quest_state("pip_whispers") == "active", "Pip dialogue did not start quest")
	assert(GameState.quest_domain.quest_step_index("pip_whispers") == 1, "Quest did not advance past its opening talk objective")
	assert(GameState.quest_domain.tracked_quest() == "pip_whispers", "Started quest was not automatically tracked")
	dialogue.open("wanderer_pip")
	assert(dialogue._node_id == "whispers_active", "Reopened dialogue did not resolve active quest branch")
	dialogue._finish_typing()
	(dialogue._choices_box.get_child(0) as Button).pressed.emit()
	assert(not dialogue.visible)
	print("PIP QUEST ACTION: PASS (dialogue acceptance -> active quest -> opening talk step -> auto-track -> active follow-up)")

	# Drive the production world-monster victory handler with two kills already
	# recorded; the third authored glade_wisp defeat must complete the objective.
	GameState.quest_domain.quests["pip_whispers"] = {"state": "active", "step": 1, "progress": 2}
	var monster_scene := load("res://scenes/world/roaming_monster.tscn") as PackedScene
	assert(monster_scene != null)
	var monster := monster_scene.instantiate() as RoamingMonster
	monster.group_id = "pip_whispers_qa_fixture"
	monster.visual_definition = {"id": "glade_wisp"}
	get_tree().root.add_child(monster)
	await get_tree().process_frame
	monster.engaged = true
	monster._on_battle_finished({"group_id": "pip_whispers_qa_fixture", "victory": true})
	assert(GameState.quest_domain.quest_step_index("pip_whispers") == 2, "World victory did not complete Pip's third-wisp objective")
	assert(int(GameState.quest_domain.quests["pip_whispers"].get("progress", -1)) == 0)
	print("PIP WORLD VICTORY QUEST HOOK: PASS (third glade_wisp victory advances to Pip turn-in)")
	monster.queue_free()
	await get_tree().process_frame
	# Restore the user's pre-test quest state and tracked quest before exit.
	GameState.quest_domain.quests = previous_quests
	GameState.quest_domain.flags = previous_flags
	GameState.queue_save()

	print("PIP FAREWELL: PASS (choice closes dialogue)")
	print("ROYAL GARDENS NPC DIALOGUE TRANSITIONS: PASS")
	dialogue.queue_free()
	await get_tree().process_frame
	get_tree().quit(0)
