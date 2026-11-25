extends Node

const WORLD_PATH := "res://scenes/world/castle_royal_gardens.tscn"

func _ready() -> void:
	call_deferred("_run")

func _find_path(start: Vector2i, goal: Vector2i) -> Array[Vector2i]:
	var queue: Array[Vector2i] = [start]
	var previous: Dictionary = {start: start}
	while not queue.is_empty():
		var cell: Vector2i = queue.pop_front()
		if cell == goal:
			break
		for step in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			var next: Vector2i = cell + step
			if CastleLayout.is_path(next.x, next.y) and not previous.has(next):
				previous[next] = cell
				queue.append(next)
	if not previous.has(goal):
		return []
	var path: Array[Vector2i] = [goal]
	var cursor := goal
	while cursor != start:
		cursor = previous[cursor]
		path.push_front(cursor)
	return path

func _run() -> void:
	var packed := load(WORLD_PATH) as PackedScene
	assert(packed != null, "Royal Gardens world scene must load")
	var world := packed.instantiate() as CastleRoyalGardens
	assert(world != null, "Royal Gardens world must instantiate")
	get_tree().root.add_child(world)
	var world_runtime := world.get_node_or_null("WorldRuntime")
	if world_runtime != null:
		world_runtime.set_process(false)
	await get_tree().process_frame
	await get_tree().physics_frame

	var player := world.player
	assert(player != null and player.locomotion_component != null, "Player locomotion component must be ready")
	var locomotion := player.locomotion_component
	var touch_input := get_tree().root.get_node_or_null("TouchInput")
	assert(touch_input != null, "TouchInput autoload must be available")
	for cell in CastleLayout.WEST_POND_BYPASS:
		var bypass_position := IsoMath.grid_to_world(float(cell.x), float(cell.y))
		assert(world.is_walkable(bypass_position), "Authored pond bypass cell must remain walkable: %s" % cell)
	assert(not world.is_walkable(IsoMath.grid_to_world(24.0, 10.0)), "Pond cells must remain non-walkable")
	print("POND EDGE ROUTE: PASS (bypass cells walkable; pond cells blocked by world walkability query)")
	var shoreline_path := _find_path(Vector2i(23, 12), Vector2i(26, 11))
	assert(shoreline_path.size() >= 2, "Authored stepping-stone bypass must have a connected path around the west pond")
	player.global_position = world.to_global(IsoMath.grid_to_world(float(shoreline_path[0].x), float(shoreline_path[0].y)))
	player.velocity = Vector2.ZERO
	for path_index in range(1, shoreline_path.size()):
		var cell: Vector2i = shoreline_path[path_index]
		var target := world.to_global(IsoMath.grid_to_world(float(cell.x), float(cell.y)))
		var reached := false
		for frame in range(90):
			var delta_to_target := target - player.global_position
			if delta_to_target.length() <= 5.0:
				reached = true
				break
			touch_input.set("move_vector", delta_to_target.normalized())
			await get_tree().physics_frame
			assert(not locomotion._in_water, "Player must remain dry while walking the authored pond bypass")
		assert(reached or player.global_position.distance_to(target) <= 7.0, "Player must physically reach bypass cell %s; actual=%s target=%s" % [cell, player.global_position, target])
	assert(not locomotion._in_water, "Player must remain dry after completing the pond bypass")
	print("WEST POND SHORELINE TRAVERSAL: PASS (%d authored path cells traversed without entering water)" % shoreline_path.size())
	var east_shoreline_path := _find_path(Vector2i(28, 7), Vector2i(32, 3))
	assert(east_shoreline_path.size() >= 2, "East pond shoreline must have a connected authored route")
	player.global_position = world.to_global(IsoMath.grid_to_world(float(east_shoreline_path[0].x), float(east_shoreline_path[0].y)))
	player.velocity = Vector2.ZERO
	for path_index in range(1, east_shoreline_path.size()):
		var east_cell: Vector2i = east_shoreline_path[path_index]
		var east_target := world.to_global(IsoMath.grid_to_world(float(east_cell.x), float(east_cell.y)))
		var east_reached := false
		for frame in range(90):
			var east_delta := east_target - player.global_position
			if east_delta.length() <= 5.0:
				east_reached = true
				break
			touch_input.set("move_vector", east_delta.normalized())
			await get_tree().physics_frame
			assert(not locomotion._in_water, "Player must remain dry while traversing the east pond shoreline")
		assert(east_reached or player.global_position.distance_to(east_target) <= 7.0, "Player must physically reach east shoreline cell %s" % east_cell)
	assert(not locomotion._in_water, "Player must remain dry after completing the east pond route")
	print("EAST POND SHORELINE TRAVERSAL: PASS (%d authored path cells traversed without entering water)" % east_shoreline_path.size())
	# Assert that the paired forward/reverse routes really cover every
	# cardinal direction before physically traversing the return journeys.
	var route_directions: Dictionary = {}
	for route_variant in [shoreline_path, east_shoreline_path]:
		var route_cells: Array[Vector2i] = route_variant
		for route_step_index in range(1, route_cells.size()):
			var route_step: Vector2i = route_cells[route_step_index] - route_cells[route_step_index - 1]
			route_directions[route_step] = true
			route_directions[-route_step] = true
	for cardinal_direction in [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]:
		assert(route_directions.has(cardinal_direction), "Authored pond bypass routes must exercise cardinal direction %s" % cardinal_direction)
	# Walk both authored bypasses in reverse as well, exercising those directions
	# through the real player physics and collision solver.
	var reverse_routes := [shoreline_path, east_shoreline_path]
	for route_index in range(reverse_routes.size()):
		var reverse_path: Array[Vector2i] = reverse_routes[route_index]
		player.global_position = world.to_global(IsoMath.grid_to_world(float(reverse_path[-1].x), float(reverse_path[-1].y)))
		player.velocity = Vector2.ZERO
		for path_index in range(reverse_path.size() - 2, -1, -1):
			var reverse_cell: Vector2i = reverse_path[path_index]
			var reverse_target := world.to_global(IsoMath.grid_to_world(float(reverse_cell.x), float(reverse_cell.y)))
			var reverse_reached := false
			for frame in range(90):
				var reverse_delta := reverse_target - player.global_position
				if reverse_delta.length() <= 5.0:
					reverse_reached = true
					break
				touch_input.set("move_vector", reverse_delta.normalized())
				await get_tree().physics_frame
				assert(not locomotion._in_water, "Player must remain dry on reverse pond bypass")
			assert(reverse_reached or player.global_position.distance_to(reverse_target) <= 7.0, "Player must physically reach reverse bypass cell %s; actual=%s target=%s" % [reverse_cell, player.global_position, reverse_target])
		assert(not locomotion._in_water, "Player must remain dry after reverse pond bypass")
	print("FOUR-DIRECTION POND BYPASS: PASS (west and east routes traversed forward and backward with authored collision and water checks)")
	# Diagonal touch input must be normalized to the same speed budget as a
	# cardinal input; otherwise players gain a movement-speed exploit on diagonals.
	var speed_test_position := world.to_global(IsoMath.grid_to_world(18.0, 10.0))
	assert(world.is_walkable(world.to_local(speed_test_position)), "Diagonal speed test must start on clear walkable ground")
	player.global_position = speed_test_position
	player.velocity = Vector2.ZERO
	touch_input.set("move_vector", Vector2.DOWN)
	for frame in range(8):
		await get_tree().physics_frame
	var cardinal_speed := player.velocity.length()
	touch_input.set("move_vector", Vector2.ZERO)
	player.velocity = Vector2.ZERO
	player.global_position = speed_test_position
	touch_input.set("move_vector", Vector2(1.0, 1.0))
	for frame in range(8):
		await get_tree().physics_frame
	var diagonal_speed := player.velocity.length()
	assert(cardinal_speed > 100.0, "Cardinal touch input must accelerate the player")
	assert(diagonal_speed <= cardinal_speed * 1.05 and diagonal_speed >= cardinal_speed * 0.90, "Diagonal input must not exceed the cardinal speed budget; cardinal=%s diagonal=%s" % [cardinal_speed, diagonal_speed])
	print("DIAGONAL SPEED NORMALIZATION: PASS (cardinal=%0.1f diagonal=%0.1f)" % [cardinal_speed, diagonal_speed])
	touch_input.set("move_vector", Vector2.RIGHT)
	player.velocity = Vector2.ZERO
	player.global_position = world.to_global(IsoMath.grid_to_world(24.0, 10.5))
	assert(world.is_water_world(world.to_local(player.global_position)), "Player test position must be inside the west pond")
	for frame in range(18):
		await get_tree().physics_frame
	assert(locomotion._in_water, "Locomotion must detect the player inside the authored pond")
	assert(locomotion._speed_target < PlayerLocomotionComponent.WALK_SPEED, "Water must reduce the locomotion speed target; actual=%s" % locomotion._speed_target)
	print("POND LOCOMOTION: PASS (world-local coordinate conversion detects water and reduces speed)")

	touch_input.set("move_vector", Vector2.ZERO)
	player.velocity = Vector2.ZERO
	player.global_position = world.to_global(IsoMath.grid_to_world(18.0, 10.0))
	locomotion.physics_step(1.0 / 60.0)
	assert(not locomotion._in_water, "Locomotion must leave water state on nearby dry garden grass")
	print("DRY GROUND RECOVERY: PASS (water movement state clears on grass)")

	# The top-level camera must stay locked to the physics-driven player without
	# a second Camera2D smoothing pass introducing a competing follow target.
	var camera_rig := player.get_node("Camera2D") as PlayerCameraRig
	assert(camera_rig != null and not camera_rig.position_smoothing_enabled, "Camera must use one follow controller")
	touch_input.set("move_vector", Vector2.RIGHT)
	var max_camera_target_error := 0.0
	for frame in range(12):
		await get_tree().physics_frame
		await get_tree().process_frame
		var expected_camera_position := player.global_position + player.global_transform.basis_xform(camera_rig._follow_local_offset)
		max_camera_target_error = maxf(max_camera_target_error, camera_rig.global_position.distance_to(expected_camera_position))
	assert(max_camera_target_error <= 0.05, "Camera follow must remain locked during movement; max error=%0.4f" % max_camera_target_error)
	print("CAMERA FOLLOW STABILITY: PASS (12 moving frames; max target error=%0.4f)" % max_camera_target_error)

	touch_input.set("move_vector", Vector2.ZERO)
	world.queue_free()
	await get_tree().process_frame
	get_tree().quit(0)
