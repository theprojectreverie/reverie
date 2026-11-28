extends SceneTree

const SCENE := "res://scenes/world/six_zone_reverie/individual_zones/zone_03_willow_fields_standalone.tscn"
var player: CharacterBody2D
var touch: Node
var failures: Array[String] = []
var steps := 0

func _initialize() -> void:
	call_deferred("_run")

func _walk_to(target: Vector2) -> bool:
	var zone := current_scene
	var guard := 0
	while is_instance_valid(player) and player.global_position.distance_to(target) > 13.0 and guard < 2000:
		var delta := target - player.global_position
		touch.set_move_vector(delta.normalized() * clampf(delta.length() / 45.0, 0.25, 0.88))
		await physics_frame
		if current_scene != zone or not is_instance_valid(player):
			touch.release()
			return false
		steps += 1
		guard += 1
	touch.release()
	for i in range(8):
		await physics_frame
	return is_instance_valid(player) and player.global_position.distance_to(target) < 28.0

func _run() -> void:
	if OS.get_environment("REVERIE_E2E_DISABLE_LOCAL_SAVE") != "1":
		quit(2)
		return
	root.get_node("GameState").quest_domain.flags["tutorial_complete"] = true
	touch = root.get_node("TouchInput")
	change_scene_to_file(SCENE)
	await scene_changed
	for i in range(8):
		await physics_frame
	var zone := current_scene
	player = zone.checkpoint_player
	var pavilion: Node2D = zone.get_node("Zone/ForgottenPavilion")
	var route: Array[Vector2] = [
		Vector2(900, 1660),
		Vector2(930, 1703),
		Vector2(1160, 1588),
		Vector2(1300, 1518),
		pavilion.get_node("Entrance").global_position,
		pavilion.to_global(Vector2(122, 162)),
		pavilion.get_node("BossCourtyard").global_position,
		Vector2(1700, 1313),
		Vector2(1600, 1200),
		Vector2(1520, 1080),
		Vector2(1700, 1313),
		pavilion.get_node("BossCourtyard").global_position,
		pavilion.get_node("Entrance").global_position,
		Vector2(1300, 1518),
		Vector2(1160, 1588)
	]
	Engine.time_scale = 4.0
	for target in route:
		if not await _walk_to(target):
			failures.append("walk failed at %s, player=%s" % [target, player.global_position if is_instance_valid(player) else "freed"])
			break
	Engine.time_scale = 1.0
	touch.release()
	print("PAVILION PLAYER WALK steps=", steps, " failures=", failures)
	if is_instance_valid(current_scene):
		current_scene.queue_free()
	for i in range(3):
		await process_frame
	root.get_node("AudioDirector").stop_all_audio_immediately()
	await create_timer(0.35).timeout
	quit(0 if failures.is_empty() else 1)
