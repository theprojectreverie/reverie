extends SceneTree

class NavigationProbeWorld:
	extends Node2D
	var received_position := Vector2.ZERO
	func is_walkable(position: Vector2) -> bool:
		received_position = position
		return true

func _initialize() -> void:
	var world := NavigationProbeWorld.new()
	world.position = Vector2(-80.0, 45.0)
	world.rotation = -0.2
	world.scale = Vector2(1.3, 0.9)
	world.add_to_group("world")
	root.add_child(world)
	var entities := Node2D.new()
	entities.position = Vector2(120.0, 60.0)
	entities.rotation = 0.4
	entities.scale = Vector2(0.8, 1.2)
	world.add_child(entities)
	var monster := Node2D.new()
	monster.position = Vector2(25.0, -15.0)
	entities.add_child(monster)
	var behavior := EnemyRoamingBehavior.new()
	root.add_child(behavior)
	await process_frame
	var local_target := Vector2(5.0, 6.0)
	var expected_world_local := world.to_local(monster.to_global(local_target))
	assert(behavior._target_walkable(local_target, monster), "Walkability probe should return mock world's result")
	assert(world.received_position.is_equal_approx(expected_world_local), "Roaming target must be converted from monster-parent local to world-local coordinates")
	behavior.queue_free()
	world.queue_free()
	await process_frame
	print("ENEMY ROAMING COORDINATES: PASS (transformed NPC targets normalized for world navigation)")
	quit(0)
