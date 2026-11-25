extends Node

const WORLD_PATH := "res://scenes/world/castle_royal_gardens.tscn"

func _ready() -> void:
	call_deferred("_run")

func _run() -> void:
	print("ROYAL GARDENS NPC AUDIT: starting")
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
	var npcs: Array = world.get_world_npcs()
	assert(npcs.size() == 3, "Royal Gardens must spawn its three authored NPC placements; got %d" % npcs.size())
	var seen := {}
	for npc in npcs:
		assert(npc is WorldNPC, "Every authored placement must create a WorldNPC")
		assert(not npc.npc_id.is_empty() and not npc.display_name.is_empty() and not npc.dialogue_id.is_empty(), "NPC identity and dialogue binding must be populated")
		assert(not seen.has(npc.npc_id), "NPC IDs must be unique: %s" % npc.npc_id)
		seen[npc.npc_id] = true
		assert(npc.visual != null and npc.visual.animator != null, "NPC visual and idle animator must initialize: %s" % npc.npc_id)
		assert(npc._name_label.text == npc.display_name, "Name label must match authored identity: %s" % npc.npc_id)
		assert(npc._subtitle_label.text == npc.role, "Role subtitle must match authored placement: %s" % npc.npc_id)
		var local_position: Vector2 = npc.position
		assert(not world.is_water_world(local_position), "NPC must not spawn in a pond: %s" % npc.npc_id)
		print("NPC OK: %s | %s | role=%s | pos=%s" % [npc.npc_id, npc.display_name, npc.role, local_position])
	print("ROYAL GARDENS NPC AUDIT: PASS (%d authored NPCs; unique identity, dialogue, visuals, labels and dry placement)" % npcs.size())
	world.queue_free()
	await get_tree().process_frame
	get_tree().quit(0)
