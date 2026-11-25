extends Node
const WORLD_PATH := "res://scenes/world/greenward_world.tscn"
const REGION_ID := "elderwood_grove"

func _ready() -> void:
	call_deferred("_run")

func _run() -> void:
	print("REGION NATURAL MONSTER ROAMING: starting")
	var packed := load(WORLD_PATH) as PackedScene
	assert(packed != null)
	var world := packed.instantiate() as GreenwardWorld
	assert(world != null)
	world.region_id = REGION_ID
	get_tree().root.add_child(world)
	print("NATURAL ROAM QA: world instantiated")
	var runtime := world.get_node_or_null("WorldRuntime")
	if runtime != null:
		runtime.set_process(false)
		runtime.set_physics_process(false)
	await get_tree().process_frame
	await get_tree().physics_frame
	print("NATURAL ROAM QA: world process frame and physics frame completed")

	var player := Node2D.new()
	player.name = "NaturalRoamingDummyPlayer"
	player.add_to_group("player")
	world.add_child(player)
	await get_tree().process_frame
	print("NATURAL ROAM QA: dummy player registered; inspecting monsters")

	var monsters: Array = world.monsters
	assert(monsters.size() == 3, "Expected three authored Elderwood monsters")
	var starts: Dictionary = {}
	var initial_targets: Dictionary = {}
	var last_targets: Dictionary = {}
	var target_changes: Dictionary = {}
	for monster in monsters:
		assert(monster is RoamingMonster)
		assert(monster.roaming_behavior != null, "Monster missing scene-owned roaming behavior")
		monster.set_process(false) # The test invokes _process() with controlled deltas below.
		starts[monster.get_instance_id()] = monster.position
		initial_targets[monster.get_instance_id()] = monster.get("_roam_target")
		last_targets[monster.get_instance_id()] = monster.get("_roam_target")
		target_changes[monster.get_instance_id()] = 0

	# Exercise the real RoamingMonster._process path at fixed 0.25s steps.
	# This avoids coupling the smoke test to a long-running headless frame pump,
	# while retaining the real scene-owned component graph and physics queries.
	print("NATURAL ROAM QA: all three monsters initialized; starting 18-second deterministic process observation")
	for step in range(72):
		for monster in monsters:
			monster._process(0.25)
			var key: int = monster.get_instance_id()
			var target: Vector2 = monster.get("_roam_target")
			if not target.is_equal_approx(last_targets[key]):
				target_changes[key] = int(target_changes[key]) + 1
				last_targets[key] = target
			assert(not monster.engaged, "Passive roaming unexpectedly started an encounter")
			assert(not monster.defeated)
			var movement: Node = monster.movement_component
			var home: Vector2 = movement.get("home_position")
			var radius: float = movement.get("roam_radius")
			assert(target.distance_to(home) <= radius + 0.01, "Natural process selected target outside home radius")
			assert(monster.position.distance_to(home) <= radius + 1.0, "Natural process moved monster outside home radius")

	var moved_count := 0
	var target_count := 0
	for monster in monsters:
		var key: int = monster.get_instance_id()
		var start: Vector2 = starts[key]
		var target: Vector2 = monster.get("_roam_target")
		if not monster.position.is_equal_approx(start):
			moved_count += 1
		if not target.is_equal_approx(initial_targets[key]):
			target_count += 1
		assert(int(target_changes[key]) >= 2, "Natural process did not complete multiple destination cycles for %s" % monster.group_id)
		print("NATURAL ROAM RESULT: %s | moved=%s | destination_changes=%d | target=%s | home_distance=%.1f" % [
			monster.group_id,
			str(not monster.position.is_equal_approx(start)),
			int(target_changes[key]),
			str(target),
			monster.position.distance_to(monster.home_position)
		])
	assert(target_count == monsters.size(), "Not every live monster selected a destination through _process")
	assert(moved_count == monsters.size(), "Not every live monster moved through _process")
	print("REGION NATURAL MONSTER ROAMING: PASS (%d/%d selected and moved via deterministic _process calls)" % [moved_count, monsters.size()])
	for monster in monsters:
		monster.set_process(false)
	world.queue_free()
	await get_tree().process_frame
	get_tree().quit(0)
