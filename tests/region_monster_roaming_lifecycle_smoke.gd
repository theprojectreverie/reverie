extends Node
const WORLD_PATH := "res://scenes/world/greenward_world.tscn"
const REGION_ID := "elderwood_grove"

func _ready() -> void:
	call_deferred("_run")

func _run() -> void:
	print("REGION MONSTER ROAMING LIFECYCLE: starting")
	var packed := load(WORLD_PATH) as PackedScene
	assert(packed != null)
	var world := packed.instantiate() as GreenwardWorld
	assert(world != null)
	world.region_id = REGION_ID
	get_tree().root.add_child(world)
	var runtime := world.get_node_or_null("WorldRuntime")
	if runtime != null:
		runtime.set_process(false)
		runtime.set_physics_process(false)
	await get_tree().process_frame
	await get_tree().physics_frame

	var player := Node2D.new()
	player.name = "RoamingLifecycleDummyPlayer"
	player.add_to_group("player")
	world.add_child(player)
	var behavior := EnemyRoamingBehavior.new()
	get_tree().root.add_child(behavior)
	await get_tree().process_frame

	var monsters: Array = world.monsters
	assert(monsters.size() == 3, "Expected all three authored Elderwood spawns")
	var completed_cycles := 0
	for monster in monsters:
		assert(monster is RoamingMonster)
		monster.set_process(false)
		var movement: Node = monster.movement_component
		assert(movement != null)
		var start: Vector2 = monster.position
		movement.set("home_position", start)
		movement.set("roam_radius", 70.0)
		monster.set("_roam_target", start)
		movement.set("_roam_timer", 0.01)

		# Expire the real roam timer and let the production behavior choose a
		# collision-checked target around the monster's current home.
		behavior.process_roaming(monster, player, 0.02)
		var first_target: Vector2 = monster.get("_roam_target")
		assert(first_target.distance_to(start) <= 70.001, "First destination escaped home radius")
		assert(behavior._target_walkable(first_target, monster), "First destination is not walkable")
		assert(movement.get("_roam_timer") > 0.0, "Roam timer was not reset after selection")
		print("TIMER / DESTINATION: PASS | %s | %s" % [monster.group_id, first_target])

		# Force a nearby clear destination to exercise the production movement
		# path deterministically, while keeping the world and monster real.
		var movement_target := Vector2.ZERO
		var found := false
		for radius in [16.0, 24.0, 32.0, 40.0]:
			for direction_index in 32:
				var angle: float = TAU * float(direction_index) / 32.0
				var candidate: Vector2 = start + Vector2(cos(angle), sin(angle)) * radius
				if behavior._target_walkable(candidate, monster):
					movement_target = candidate
					found = true
					break
			if found:
				break
		assert(found, "No clear nearby destination for %s" % monster.group_id)
		monster.set("_roam_target", movement_target)
		movement.set("current_target_position", movement_target)
		movement.set("_roam_timer", 10.0)
		movement.set("move_speed", 30.0)
		var moved := false
		for _step in 20:
			var before: Vector2 = monster.position
			behavior.process_roaming(monster, player, 0.1)
			if not monster.position.is_equal_approx(before):
				moved = true
			if monster.position.distance_to(movement_target) <= 4.0:
				break
		assert(moved, "Monster did not move toward a clear destination")
		assert(monster.position.distance_to(movement_target) <= 4.0, "Monster failed to arrive at its destination")
		assert(monster.get("_roam_target").is_equal_approx(movement_target))
		print("MOVEMENT / ARRIVAL: PASS | %s" % monster.group_id)

		# Once the timer expires again, a new destination should be selected.
		var arrived_position: Vector2 = monster.position
		movement.set("_roam_timer", 0.01)
		behavior.process_roaming(monster, player, 0.02)
		var next_target: Vector2 = monster.get("_roam_target")
		assert(next_target.distance_to(movement_target) > 4.0, "Next roaming cycle kept the previous destination")
		assert(next_target.distance_to(start) <= 70.001, "Next cycle escaped the authored home radius")
		assert(behavior._target_walkable(next_target, monster), "Next cycle selected a blocked destination")
		assert(movement.get("_roam_timer") > 0.0)
		completed_cycles += 1
		print("NEXT ROAM CYCLE: PASS | %s | from=%s to=%s" % [monster.group_id, arrived_position, next_target])

	assert(completed_cycles == monsters.size())
	print("REGION MONSTER ROAMING LIFECYCLE: PASS (%d complete timer-selection-movement-arrival-next cycles)" % completed_cycles)
	behavior.queue_free()
	world.queue_free()
	await get_tree().process_frame
	get_tree().quit(0)
