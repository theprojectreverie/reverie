extends Node
const MOCK = preload("res://tests/elathra_audience_mock.gd")
const QUEST := "elathra_first_audience"
func _ready() -> void:
	call_deferred("_run")
func _run() -> void:
	if AuthGateway.is_authenticated() or OS.get_environment("REVERIE_E2E_DISABLE_LOCAL_SAVE")!="1":
		get_tree().quit(2)
		return
	var mock := MOCK.new()
	mock.name = "StoryGardenCombatSync"
	add_child(mock)
	var domain := GameState.quest_domain
	var before := domain.quests.duplicate(true)
	var dialogue := (load("res://scenes/ui/elathra_dialogue_box.tscn") as PackedScene).instantiate()
	add_child(dialogue)
	dialogue.open_story(mock)
	assert(dialogue._node_id=="greet" and domain.quest_state(QUEST)=="not_started")
	assert(not domain.start_quest(QUEST,"elathra"))
	var portal := Area2D.new()
	portal.set_script(preload("res://scripts/world/six_zone_reverie/zone_transfer_trigger.gd"))
	portal.required_quest = QUEST
	portal.previously_visited_zone = "StandaloneZone02"
	add_child(portal)
	assert(not portal._story_unlocked())
	var hear: Dictionary = dialogue._node.choices[0]
	mock.responses.assign([{}, {"audience":{"state":"active"}}, {"audience":{"state":"complete"}}])
	dialogue._finish_typing()
	await dialogue._choose(hear)
	assert(dialogue._node_id=="greet" and mock.calls==["hear"] and domain.quests==before)
	await dialogue._choose(hear)
	assert(dialogue._node_id=="accepted" and domain.quest_state(QUEST)=="active" and domain.quest_step_index(QUEST)==1)
	assert(not domain.complete_quest(QUEST))
	dialogue.close()
	dialogue.open_story(mock)
	assert(dialogue._node_id=="accepted")
	dialogue._finish_typing()
	await dialogue._choose(dialogue._node.choices[0])
	assert(dialogue._node_id=="complete" and domain.quest_state(QUEST)=="complete" and domain.quest_step_index(QUEST)==2)
	assert(mock.calls==["hear","hear","accept"] and domain.quests==before)
	assert(portal._story_unlocked())
	dialogue.close()
	dialogue.open_story(mock)
	assert(dialogue._node_id=="complete")
	dialogue.close()
	dialogue.queue_free()
	mock.queue_free()
	portal.queue_free()
	await get_tree().process_frame
	assert(domain.quests==before)
	print("PASS Elathra dialogue retry, resume, transient journal, no local quest mutation")
	await AudioDirector.drain_for_shutdown()
	get_tree().quit(0)
