extends SceneTree

const WORLD_SCENE := "res://scenes/world/castle_royal_gardens.tscn"

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var packed := load(WORLD_SCENE) as PackedScene
	assert(packed != null)
	var world := packed.instantiate() as Node2D
	root.add_child(world)
	for _i in range(12):
		await physics_frame
	var player := world.get("player") as CharacterBody2D
	assert(player != null)
	var camera := player.get_node("Camera2D") as PlayerCameraRig
	assert(camera != null)
	player.set("input_enabled", true)
	Input.action_press("move_right")
	var previous_player := player.global_position
	var previous_camera := camera.global_position
	var max_target_error := 0.0
	var max_camera_step := 0.0
	var max_player_step := 0.0
	for i in range(90):
		await physics_frame
		var expected := player.global_position + player.global_transform.basis_xform(camera._follow_local_offset)
		var target_error := camera.global_position.distance_to(expected)
		max_target_error = maxf(max_target_error, target_error)
		max_camera_step = maxf(max_camera_step, camera.global_position.distance_to(previous_camera))
		max_player_step = maxf(max_player_step, player.global_position.distance_to(previous_player))
		if i % 15 == 0:
			print("MOTION_SAMPLE tick=", i, " player=", player.global_position, " camera=", camera.global_position, " target_error=", target_error, " canvas=", camera.get_viewport().get_canvas_transform())
		previous_player = player.global_position
		previous_camera = camera.global_position
	Input.action_release("move_right")
	print("MOTION_SYNC max_target_error=", max_target_error, " max_camera_step=", max_camera_step, " max_player_step=", max_player_step, " world_scale=", world.global_transform.get_scale())
	world.queue_free()
	quit(0 if max_target_error < 0.1 and max_player_step > 0.0 else 1)

