extends SceneTree

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var packed := load("res://scenes/world/castle_royal_gardens.tscn") as PackedScene
	assert(packed != null, "Royal Gardens scene must load")
	var world := packed.instantiate() as Node2D
	root.add_child(world)
	for frame in range(6):
		await physics_frame

	var npcs: Array = world.get("npcs")
	var monsters: Array = world.get("monsters")
	assert(npcs.size() == 3, "Royal Gardens should contain only the two gate guards and Pip")
	var npc_ids: Array[String] = []
	for npc in npcs:
		npc_ids.append(str(npc.get("npc_id")))
	assert(npc_ids.has("castle_guard_left") and npc_ids.has("castle_guard_right") and npc_ids.has("garden_visitor"), "Approved NPC roster is incomplete")
	assert(not npc_ids.has("royal_gardener"), "Royal Gardener must not spawn in the clean garden")
	print("GARDEN NPC ROSTER: PASS (2 gate guards + Pip; no Royal Gardener)")
	assert(monsters.is_empty(), "No Gothic Sentinels or unrelated monsters should spawn in the formal garden")
	print("GARDEN ENCOUNTERS: PASS (no unrelated sentinel spawns)")

	var interactables := world.get_node_or_null("ExpansionBuilder/ExpansionInteractables") as Node2D
	assert(interactables != null and interactables.is_visible_in_tree(), "Expansion interactable layer must remain active")
	assert(interactables.get_node_or_null("InteractiveProp") == null, "Gardener Seal Cache must not spawn")
	print("GARDEN COLLECTIBLES: PASS (Gardener Seal Cache removed)")

	var portal: Node = interactables.get_node_or_null("RegionPortal") if interactables != null else null
	assert(portal != null and portal.is_visible_in_tree(), "Road to the Gothic Castle portal must remain visible")
	assert(str(portal.get("target_region")) == "gothic_castle_boss_zone", "Royal Road must target the Gothic Castle zone")
	assert(str(portal.get("entry_point")) == "royal_gate", "Royal Road must use the Gothic Castle royal gate entry")
	assert(str(portal.get("required_quest")).is_empty(), "Royal Road must no longer be locked behind removed garden sentinels")
	assert(bool(portal.call("can_interact")), "Royal Road portal must be interactable")
	print("GOTHIC CASTLE ROAD: PASS (visible, interactable, unlocked, correct destination)")

	var quest_marker := world.get_node_or_null("Entities/QuestDestinationMarker")
	assert(quest_marker != null, "Shared quest marker infrastructure must remain available")
	print("QUEST MARKER INFRASTRUCTURE: PASS")
	world.queue_free()
	quit(0)
