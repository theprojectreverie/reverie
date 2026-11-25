extends Node

const WORLD_PATH := "res://scenes/world/castle_royal_gardens.tscn"

var dialogue_events: Array[String] = []

func _ready() -> void:
	call_deferred("_run")

func _on_dialogue_requested(dialogue_id: String) -> void:
	dialogue_events.append(dialogue_id)

func _run() -> void:
	print("ROYAL GARDENS NPC INTERACTION AUDIT: starting")
	EventBus.dialogue_requested.connect(_on_dialogue_requested)
	var packed := load(WORLD_PATH) as PackedScene
	assert(packed != null, "Royal Gardens scene must load")
	var world := packed.instantiate() as CastleRoyalGardens
	assert(world != null, "Royal Gardens scene must instantiate")
	get_tree().root.add_child(world)
	var runtime := world.get_node_or_null("WorldRuntime")
	if runtime != null:
		runtime.set_process(false)
	await get_tree().process_frame
	await get_tree().physics_frame
	var player: Player = world.player
	var npcs: Array = world.get_world_npcs()
	assert(player != null and player.interaction_component != null, "Player interaction component must initialize")
	assert(npcs.size() == 3, "All three authored NPCs must be present")
	var interaction := player.interaction_component
	for npc in npcs:
		player.global_position = npc.global_position + Vector2(0.0, 24.0)
		assert(interaction.refresh_nearest() == npc, "Nearest NPC must be selected within its interaction radius: %s" % npc.npc_id)
		assert(player.current_prompt() == "Talk", "Nearby NPC prompt must read Talk")
		var before_count := dialogue_events.size()
		assert(interaction.try_interact(), "Nearby NPC interaction should be accepted: %s" % npc.npc_id)
		assert(dialogue_events.size() == before_count + 1, "Interaction must emit exactly one dialogue request")
		assert(dialogue_events.back() == npc.dialogue_id, "Interaction must request the NPC's authored dialogue")
		print("INTERACTION OK: %s -> %s" % [npc.npc_id, npc.dialogue_id])
	player.global_position = npcs[0].global_position + Vector2(0.0, 180.0)
	assert(interaction.refresh_nearest() == null, "NPC must not be interactable outside its radius")
	assert(player.current_prompt().is_empty(), "Prompt must clear outside interaction radius")
	assert(not interaction.try_interact(), "Out-of-range interaction must be rejected")
	var event_count := dialogue_events.size()
	player.global_position = npcs[0].global_position + Vector2(0.0, 20.0)
	npcs[0].enabled = false
	assert(interaction.refresh_nearest() != npcs[0], "Disabled NPC must not be selected")
	assert(dialogue_events.size() == event_count, "Disabled NPC must not emit dialogue")
	npcs[0].enabled = true
	npcs[0].visible = false
	assert(interaction.refresh_nearest() != npcs[0], "Hidden NPC must not be selected")
	assert(dialogue_events.size() == event_count, "Hidden NPC must not emit dialogue")
	npcs[0].visible = true
	player.global_position = npcs[1].global_position + Vector2(0.0, 24.0)
	await get_tree().create_timer(0.2).timeout
	assert(interaction.get_current() == npcs[1], "Automatic scan timer must select a nearby NPC without manual refresh")
	assert(player.current_prompt() == "Talk", "Automatic scan must publish the Talk prompt")
	player.global_position = npcs[1].global_position + Vector2(0.0, 180.0)
	await get_tree().create_timer(0.2).timeout
	assert(interaction.get_current() == null, "Automatic scan timer must clear the prompt after leaving range")
	assert(player.current_prompt().is_empty(), "Automatic scan must clear stale Talk prompt")
	print("AUTOMATIC PROXIMITY SCAN: PASS (prompt appears and clears from player movement)")
	print("ROYAL GARDENS NPC INTERACTION AUDIT: PASS (3 dialogue routes; range, prompt, disabled, hidden and timed scan guards)")
	EventBus.dialogue_requested.disconnect(_on_dialogue_requested)
	world.queue_free()
	await get_tree().process_frame
	get_tree().quit(0)
