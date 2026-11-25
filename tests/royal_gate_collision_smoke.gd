extends Node2D

const PLAYER_SCENE := preload("res://scenes/characters/player.tscn")
const GATE_SCENE := preload("res://scenes/world/components/royal_gate_architecture.tscn")

var player: CharacterBody2D
var _stage := 0
var _frames := 0

func _ready() -> void:
	var gate := GATE_SCENE.instantiate()
	add_child(gate)
	player = PLAYER_SCENE.instantiate() as CharacterBody2D
	add_child(player)
	player.get_node("LocomotionComponent").set_physics_process(false)
	player.position = Vector2.ZERO
	set_physics_process(true)

func _physics_process(_delta: float) -> void:
	if _stage == 0:
		player.velocity = Vector2(-250.0, 0.0)
		player.move_and_slide()
		_frames += 1
		if _frames >= 60:
			assert(player.global_position.x > -90.0, "Player cannot pass through the left gate pier")
			assert(player.global_position.x < -65.0, "Player stops against the left gate pier")
			_stage = 1
			_frames = 0
			player.global_position = Vector2.ZERO
	elif _stage == 1:
		player.velocity = Vector2(250.0, 0.0)
		player.move_and_slide()
		_frames += 1
		if _frames >= 60:
			assert(player.global_position.x < 90.0, "Player cannot pass through the right gate pier")
			assert(player.global_position.x > 65.0, "Player stops against the right gate pier")
			_stage = 2
			_frames = 0
			player.global_position = Vector2(0.0, -40.0)
	elif _stage == 2:
		player.velocity = Vector2(0.0, 220.0)
		player.move_and_slide()
		_frames += 1
		if _frames >= 30:
			assert(player.global_position.y > 0.0, "Player can walk through the central gate opening")
			_stage = 3
			_frames = 0
			player.global_position = Vector2(-320.0, 266.0)
	elif _stage == 3:
		player.velocity = Vector2(250.0, 0.0)
		player.move_and_slide()
		_frames += 1
		if _frames >= 30:
			assert(player.global_position.x > -320.0, "Player advances toward the side fountain")
			assert(player.global_position.x < -285.0, "Player is stopped by the side fountain base collider")
			print("ROYAL_GATE_COLLISION_PASS left_wall_blocked=true right_wall_blocked=true central_opening_clear=true side_fountain_blocked=true")
			get_tree().quit(0)
