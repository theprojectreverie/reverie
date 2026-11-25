extends SceneTree

class NavigationBlockerWorld:
	extends Node2D
	var block_x := 0.0
	func is_walkable(position: Vector2) -> bool:
		return position.x < block_x

class MonsterProbe:
	extends Node2D
	var _roam_target := Vector2.ZERO

func _initialize() -> void:
	var world := NavigationBlockerWorld.new()
	world.position = Vector2(-80.0, 45.0)
	world.rotation = -0.2
	world.scale = Vector2(1.3, 0.9)
	world.block_x = 15.0
	world.add_to_group("world")
	root.add_child(world)
	var entities := Node2D.new()
	entities.position = Vector2(120.0, 60.0)
	entities.rotation = 0.4
	entities.scale = Vector2(0.8, 1.2)
	world.add_child(entities)
	var monster := MonsterProbe.new()
	monster.position = Vector2(5.0, 0.0)
	entities.add_child(monster)
	var movement := EnemyMovement.new()
	movement.move_speed = 30.0
	movement.home_position = monster.position
	root.add_child(movement)
	var behavior := EnemyRoamingBehavior.new()
	root.add_child(behavior)
	await process_frame
	var target := Vector2(40.0, 0.0)
	var before := monster.position
	var direction := behavior._move_toward_walkable_target(monster, movement, target, 1.0)
	assert(direction == Vector2.ZERO, "Blocked next movement step must stop roaming")
	assert(monster.position.is_equal_approx(before), "Monster must not cross an authored collision boundary")
	assert(monster.get("_roam_target").is_equal_approx(before), "Blocked target must be discarded instead of repeatedly pushing into the obstacle")
	world.block_x = 1000.0
	monster.set("_roam_target", target)
	direction = behavior._move_toward_walkable_target(monster, movement, target, 0.5)
	assert(direction.length() > 0.0, "Walkable next step must allow roaming movement")
	assert(monster.position.distance_to(before) > 0.0, "Monster should advance when its next step is clear")
	behavior.queue_free()
	movement.queue_free()
	world.queue_free()
	await process_frame
	print("ENEMY ROAMING COLLISION GUARD: PASS (blocked intermediate step stops; clear step advances)")
	quit(0)
