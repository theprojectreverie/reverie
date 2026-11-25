extends SceneTree

func _initialize() -> void:
	var animator := CharacterAnimator.new()
	var cases: Array[Dictionary] = [
		{"name": "right", "vector": Vector2.RIGHT, "expected": CharacterAnimator.Direction.RIGHT},
		{"name": "down-right", "vector": Vector2(1.0, 1.0), "expected": CharacterAnimator.Direction.DOWN_RIGHT},
		{"name": "down", "vector": Vector2.DOWN, "expected": CharacterAnimator.Direction.DOWN},
		{"name": "down-left", "vector": Vector2(-1.0, 1.0), "expected": CharacterAnimator.Direction.DOWN_LEFT},
		{"name": "left", "vector": Vector2.LEFT, "expected": CharacterAnimator.Direction.LEFT},
		{"name": "up-left", "vector": Vector2(-1.0, -1.0), "expected": CharacterAnimator.Direction.UP_LEFT},
		{"name": "up", "vector": Vector2.UP, "expected": CharacterAnimator.Direction.UP},
		{"name": "up-right", "vector": Vector2(1.0, -1.0), "expected": CharacterAnimator.Direction.UP_RIGHT},
	]
	for case in cases:
		var actual := animator.set_direction_from_vector(case.vector)
		if actual != case.expected:
			push_error("Direction mapping failed for %s: expected %d, got %d" % [case.name, case.expected, actual])
			quit(1)
			return
	print("PASS: all eight cardinal and diagonal movement vectors map to the expected sprite directions.")

	animator.set_direction(CharacterAnimator.Direction.LEFT)
	var retained := animator.set_direction_from_vector(Vector2.ZERO)
	if retained != CharacterAnimator.Direction.LEFT:
		push_error("Zero movement vector must preserve the current direction")
		quit(1)
		return
	print("PASS: zero movement preserves the current facing direction.")

	# Exact half-sector ties advance clockwise to the next direction sector.
	var tie_down_right := Vector2(cos(PI / 8.0), sin(PI / 8.0))
	var tie_right := Vector2(cos(15.0 * PI / 8.0), sin(15.0 * PI / 8.0))
	if animator.set_direction_from_vector(tie_down_right) != CharacterAnimator.Direction.DOWN_RIGHT:
		push_error("22.5-degree tie must resolve clockwise to DOWN_RIGHT")
		quit(1)
		return
	if animator.set_direction_from_vector(tie_right) != CharacterAnimator.Direction.RIGHT:
		push_error("337.5-degree tie must wrap clockwise to RIGHT")
		quit(1)
		return
	print("PASS: exact 22.5-degree sector ties resolve clockwise, including wraparound.")
	quit(0)
