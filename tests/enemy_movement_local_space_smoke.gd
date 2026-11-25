extends SceneTree

func _initialize() -> void:
	var parent := Node2D.new()
	parent.position = Vector2(240.0, -90.0)
	parent.rotation = 0.35
	parent.scale = Vector2(1.4, 0.8)
	root.add_child(parent)
	var monster := Node2D.new()
	monster.position = Vector2(10.0, 20.0)
	parent.add_child(monster)
	var movement := EnemyMovement.new()
	movement.move_speed = 10.0
	root.add_child(movement)
	var target := Vector2(30.0, 20.0)
	var direction := movement.move_toward_target(monster, target, 1.0)
	assert(direction.is_equal_approx(Vector2.RIGHT), "Movement direction must be computed in parent-local space")
	assert(monster.position.is_equal_approx(Vector2(20.0, 20.0)), "Movement must advance toward local target without transform contamination")
	assert(monster.global_position.distance_to(target) > 100.0, "Test transform must distinguish local and global target spaces")
	var reached := [false]
	movement.destination_reached.connect(func(_position: Vector2) -> void: reached[0] = true)
	monster.position = Vector2(28.0, 20.0)
	movement.move_toward_target(monster, target, 0.1)
	assert(reached[0], "Destination reached must be evaluated in local space")
	movement.queue_free()
	parent.queue_free()
	await process_frame
	print("ENEMY MOVEMENT LOCAL SPACE: PASS (transformed parent preserves local target and arrival checks)")
	quit(0)
