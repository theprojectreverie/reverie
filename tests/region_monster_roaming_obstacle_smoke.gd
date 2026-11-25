extends Node
const WORLD_PATH := "res://scenes/world/greenward_world.tscn"
const REGION_ID := "elderwood_grove"

func _ready() -> void:
	call_deferred("_run")

func _collect_colliders(node: Node, output: Array) -> void:
	if node is CollisionObject2D and node.collision_layer & 1 != 0:
		output.append(node)
	for child in node.get_children():
		_collect_colliders(child, output)

func _run() -> void:
	print("REGION MONSTER ROAMING OBSTACLE AUDIT: starting")
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

	var behavior := EnemyRoamingBehavior.new()
	get_tree().root.add_child(behavior)
	await get_tree().process_frame

	var monsters: Array = world.monsters
	assert(not monsters.is_empty(), "Expected actual region monster spawns")
	var blocker_stops := 0
	var clear_moves := 0
	for monster in monsters:
		if not monster is RoamingMonster:
			continue
		monster.set_process(false)
		monster.set_physics_process(false)
		var movement: Node = monster.movement_component
		assert(movement != null)
		var original_speed: float = movement.get("move_speed")
		var start: Vector2 = monster.position
		# Add an isolated, explicit physics fixture to the actual region world.
		# Elderwood currently has no layer-1 blockers in this scene variant, so
		# the test must not silently depend on unrelated village collision art.
		var selected_blocker := StaticBody2D.new()
		selected_blocker.name = "RoamingCollisionFixture_%s" % monster.group_id
		selected_blocker.collision_layer = 1
		selected_blocker.collision_mask = 0
		var blocker_shape := CollisionShape2D.new()
		var rectangle := RectangleShape2D.new()
		rectangle.size = Vector2(28.0, 28.0)
		blocker_shape.shape = rectangle
		selected_blocker.add_child(blocker_shape)
		world.add_child(selected_blocker)
		selected_blocker.global_position = monster.global_position + Vector2(40.0, 0.0)
		await get_tree().physics_frame
		var blocked_target: Vector2 = monster.to_local(selected_blocker.global_position)
		assert(not behavior._target_walkable(blocked_target, monster), "Production walkability query accepted fixture blocker for %s" % monster.group_id)
		monster.set("_roam_target", blocked_target)
		movement.set("move_speed", start.distance_to(blocked_target) + 1.0)
		var blocked_direction: Vector2 = behavior._move_toward_walkable_target(monster, movement, blocked_target, 1.0)
		assert(blocked_direction == Vector2.ZERO, "Monster advanced into authored blocker: %s" % monster.group_id)
		assert(monster.position.is_equal_approx(start), "Monster position changed despite blocked step")
		assert(monster.get("_roam_target").is_equal_approx(start), "Blocked target was not discarded")
		blocker_stops += 1
		print("ROAMING COLLISION FIXTURE STOP: PASS | %s | %s" % [monster.group_id, selected_blocker.get_path()])

		# Recovery: use the production random-target picker with the production
		# world-space collision predicate after the blocked target was discarded.
		var walkability_check := Callable(behavior, "_target_walkable").bind(monster)
		var recovery_target: Vector2 = movement.pick_roam_target(start, walkability_check)
		assert(behavior._target_walkable(recovery_target, monster), "Recovery selected a blocked destination")
		assert(recovery_target.distance_to(blocked_target) > 4.0, "Recovery retained the rejected obstacle target")
		monster.set("_roam_target", recovery_target)
		assert(monster.get("_roam_target").is_equal_approx(recovery_target))
		print("ROAM DESTINATION RECOVERY: PASS | %s | target=%s" % [monster.group_id, recovery_target])

		# Verify the same production movement helper advances on clear ground.
		var clear_target: Vector2 = start
		var found_clear := false
		for radius in [16.0, 24.0, 32.0, 48.0]:
			for direction_index in 16:
				var angle: float = TAU * float(direction_index) / 16.0
				var candidate: Vector2 = start + Vector2(cos(angle), sin(angle)) * radius
				if behavior._target_walkable(candidate, monster):
					clear_target = candidate
					found_clear = true
					break
			if found_clear:
				break
		assert(found_clear, "No nearby clear roaming step for %s" % monster.group_id)
		monster.set("_roam_target", clear_target)
		movement.set("move_speed", minf(original_speed, 24.0))
		var clear_direction: Vector2 = behavior._move_toward_walkable_target(monster, movement, clear_target, 0.5)
		assert(clear_direction.length_squared() > 0.0001, "Monster failed to move on clear ground")
		assert(not monster.position.is_equal_approx(start), "Clear-ground movement did not advance")
		clear_moves += 1
		monster.position = start
		movement.set("move_speed", original_speed)
		print("CLEAR GROUND ROAMING: PASS | %s" % monster.group_id)

	assert(blocker_stops == monsters.size(), "Not every spawned monster passed blocker stop")
	assert(clear_moves == monsters.size(), "Not every spawned monster moved on clear ground")
	print("REGION MONSTER ROAMING OBSTACLE AUDIT: PASS (%d fixture blocker stops; %d clear-ground moves)" % [blocker_stops, clear_moves])
	behavior.queue_free()
	world.queue_free()
	await get_tree().process_frame
	get_tree().quit(0)
