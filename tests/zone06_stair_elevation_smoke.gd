extends Node2D

func _ready() -> void:
	var zone := preload("res://scenes/world/six_zone_reverie/zone_06_ruined_tower.tscn").instantiate()
	add_child(zone)
	var template := preload("res://scenes/world/six_zone_reverie/individual_zones/zone_06_ruined_tower_standalone.tscn").instantiate()
	var ramp := template.get_node("PalaceStairElevation")
	template.remove_child(ramp)
	ramp.owner = null
	add_child(ramp)
	template.free()
	var player := preload("res://scenes/characters/player.tscn").instantiate() as CharacterBody2D
	player.position = Vector2(0, 1530)
	add_child(player)
	await get_tree().physics_frame
	var low: float = ramp.elevation_at(Vector2(0, 1490))
	var mid: float = ramp.elevation_at(Vector2(0, 1345))
	var high: float = ramp.elevation_at(Vector2(0, 1200))
	print("STAIR_LEVELS ", low, " ", mid, " ", high)
	var ok := is_equal_approx(low, 0.0) and is_equal_approx(mid, 56.0) and is_equal_approx(high, 112.0)
	var mid_transform := player.global_transform
	mid_transform.origin = Vector2(0, 1345)
	var left_blocked := player.test_move(mid_transform, Vector2(-300, 0))
	var right_blocked := player.test_move(mid_transform, Vector2(300, 0))
	print("RAIL_GUARDS left=", left_blocked, " right=", right_blocked)
	ok = ok and left_blocked and right_blocked
	var edge_transform := player.global_transform
	edge_transform.origin = Vector2(800, 1300)
	var front_blocked := player.test_move(edge_transform, Vector2(0, -180))
	edge_transform.origin = Vector2(1550, 1050)
	var side_blocked := player.test_move(edge_transform, Vector2(-180, 0))
	edge_transform.origin = Vector2(0, 1500)
	var stairs_clear := not player.test_move(edge_transform, Vector2(0, -310))
	print("TERRACE_EDGE_TEST front=", front_blocked, " side=", side_blocked, " stairs_clear=", stairs_clear)
	ok = ok and front_blocked and side_blocked and stairs_clear
	Input.action_press("move_up")
	for i in range(240):
		await get_tree().physics_frame
		if player.position.y < 1190.0:
			break
	Input.action_release("move_up")
	await get_tree().physics_frame
	print("ASCENT ", player.position, " height=", player.get_meta("surface_elevation", -1.0))
	ok = ok and player.position.y < 1200.0 and float(player.get_meta("surface_elevation", -1.0)) > 110.0
	Input.action_press("move_down")
	for i in range(240):
		await get_tree().physics_frame
		if player.position.y > 1510.0:
			break
	Input.action_release("move_down")
	await get_tree().physics_frame
	print("DESCENT ", player.position, " height=", player.get_meta("surface_elevation", -1.0))
	ok = ok and player.position.y > 1490.0 and is_zero_approx(float(player.get_meta("surface_elevation", -1.0)))
	print("STAIR_TEST_PASS=", ok)
	get_tree().quit(0 if ok else 1)
