class_name EnemyRoamingBehavior
extends Node
## Coordinates the passive, interaction-only roaming loop for a world enemy.
## Movement, detection, targeting, status, animation and encounter state remain
## owned by their dedicated components; this node only composes one frame.

func process_roaming(monster: Node2D, player: Node2D, delta: float) -> void:
	if monster == null or player == null:
		return
	var detection: Node = monster.get("detection_component")
	var targeting: Node = monster.get("targeting_component")
	var status: Node = monster.get("status_component")
	var movement: Node = monster.get("movement_component")
	var visual: Node = monster.get("visual")
	var animation: Node = monster.get("animation_component")
	var controller: Node = monster.get("enemy_controller")
	var state_machine: Node = monster.get("state_machine")
	if detection != null and detection.has_method("evaluate"):
		detection.call("evaluate", monster, player)
	if targeting != null and targeting.has_method("clear_target"):
		targeting.call("clear_target")
	if status != null and status.has_method("tick"):
		status.call("tick", delta)
	if movement == null:
		return
	if movement.tick_roam_timer(delta):
		var walkability_check := Callable(self, "_target_walkable").bind(monster)
		var candidate: Vector2 = movement.pick_roam_target(monster.position, walkability_check)
		movement.reset_roam_timer()
		monster.set("_roam_target", candidate)
	var target: Vector2 = monster.get("_roam_target")
	var direction := _move_toward_walkable_target(monster, movement, target, delta)
	var moving := direction.length_squared() > 0.0001
	movement.set_mode(&"patrol" if moving else &"idle")
	if visual != null:
		visual.set("walking", moving)
		if moving:
			visual.call("set_move_direction", direction)
			visual.call("play", 1)
		else:
			visual.call("play", 0)
	if animation != null and animation.has_method("play_state"):
		animation.call("play_state", &"patrol" if moving else &"idle")
	if controller != null and controller.has_method("request_state"):
		var current = state_machine.get("current_state_name") if state_machine != null and "current_state_name" in state_machine else null
		var desired: StringName = &"patrol" if moving else &"idle"
		if current != desired:
			controller.call("request_state", desired, {})
	elif state_machine != null and state_machine.has_method("set_state"):
		var current = state_machine.get("current_state_name") if "current_state_name" in state_machine else null
		var desired: StringName = &"patrol" if moving else &"idle"
		if current != desired:
			state_machine.call("set_state", desired, {})


	if controller != null and controller.has_method("process_ai"):
		controller.call("process_ai", delta, {})
	elif state_machine != null and state_machine.has_method("process_state"):
		state_machine.call("process_state", delta, {})

func _move_toward_walkable_target(monster: Node2D, movement: Node, target: Vector2, delta: float) -> Vector2:
	if monster == null or movement == null or monster.position.distance_to(target) <= 4.0:
		return Vector2.ZERO
	var step_distance := float(movement.get("move_speed")) * delta
	var proposed_position := monster.position.move_toward(target, step_distance)
	# Check the next movement step, not only the final random destination.
	# Otherwise a roaming monster can cross a wall or fountain on its way to
	# an otherwise valid point because it is moved as a plain Node2D.
	if not _target_walkable(proposed_position, monster):
		monster.set("_roam_target", monster.position)
		if "current_target_position" in movement:
			movement.set("current_target_position", monster.position)
		movement.reset_roam_timer()
		return Vector2.ZERO
	return movement.move_toward_target(monster, target, delta)


func _target_walkable(position: Vector2, monster: Node2D) -> bool:
	var world := get_tree().get_first_node_in_group("world")
	if world == null or not is_instance_valid(world):
		return true
	# Roaming positions are stored in the monster parent's local space. World
	# navigation APIs accept world-local coordinates, so normalize through
	# global space before asking about authored water/collision.
	var world_local_position := position
	if monster != null and is_instance_valid(monster) and world is Node2D:
		world_local_position = (world as Node2D).to_local(monster.to_global(position))
	if world.has_method("is_walkable") and not bool(world.call("is_walkable", world_local_position)):
		return false
	# Authored worlds may expose water zones without a full navigation grid.
	# Never let a roaming enemy choose a target inside one of those zones.
	if world.has_method("is_water_world") and bool(world.call("is_water_world", world_local_position)):
		return false
	# The region walkability API currently classifies authored water/bridges;
	# it does not include StaticBody2D props, walls or environmental blockers.
	# Probe the same world collision layer used by the player before accepting
	# a spawn/roam point or moving one step toward a target.
	if world is Node2D:
		var space := (world as Node2D).get_world_2d().direct_space_state
		if space != null:
			var footprint := CircleShape2D.new()
			footprint.radius = 12.0
			var query := PhysicsShapeQueryParameters2D.new()
			query.shape = footprint
			query.transform = Transform2D(0.0, (world as Node2D).to_global(world_local_position))
			query.collision_mask = 1
			query.collide_with_bodies = true
			query.collide_with_areas = false
			if not space.intersect_shape(query, 1).is_empty():
				return false
	return true
