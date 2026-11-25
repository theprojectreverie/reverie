extends SceneTree

func _initialize() -> void:
	var movement := EnemyMovement.new()
	movement.home_position = Vector2(120.0, -45.0)
	movement.roam_radius = 70.0
	var rng := RandomNumberGenerator.new()
	rng.seed = 20261120
	var minimum_distance := INF
	var maximum_distance := 0.0
	var sum_distance := 0.0
	for _i in 500:
		var target: Vector2 = movement.pick_roam_target(Vector2.ZERO, Callable(), rng)
		var distance: float = target.distance_to(movement.home_position)
		assert(distance <= movement.roam_radius + 0.001, "Roam target exceeded configured home radius")
		minimum_distance = minf(minimum_distance, distance)
		maximum_distance = maxf(maximum_distance, distance)
		sum_distance += distance
	var mean_distance := sum_distance / 500.0
	assert(minimum_distance >= 0.0)
	assert(maximum_distance > 55.0, "Sampling did not cover the outer roam area")
	assert(mean_distance > 43.0 and mean_distance < 50.0, "Disk sampling distribution is unexpectedly skewed")
	movement.current_target_position = Vector2(5.0, 6.0)
	var rejected := movement.pick_roam_target(Vector2(7.0, 8.0), Callable(self, "_reject_all"), rng)
	assert(rejected.is_equal_approx(Vector2(7.0, 8.0)), "Failed candidate search must hold current position")
	assert(movement.current_target_position.is_equal_approx(Vector2(7.0, 8.0)))
	movement.free()
	print("ENEMY ROAM HOME RADIUS: PASS (500/500 targets within 70px disk; mean radius %.2fpx)" % mean_distance)
	print("ENEMY ROAM BLOCKED-AREA FALLBACK: PASS (no valid candidate holds current position)")
	quit(0)

func _reject_all(_position: Vector2) -> bool:
	return false
