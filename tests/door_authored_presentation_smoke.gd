extends Node

func _ready() -> void:
	call_deferred("_run")

func _run() -> void:
	var packed := load("res://scenes/world/components/interaction/door_entrance.tscn") as PackedScene
	assert(packed != null, "door scene failed to load")
	var door := packed.instantiate() as DoorEntrance
	assert(door != null, "door root type mismatch")
	add_child(door)
	var player := door.get_node("AnimationPlayer") as AnimationPlayer
	var sprite := door.get_node("Visual/DoorSprite") as Sprite2D
	var frame := door.get_node("Visual/Frame") as Sprite2D
	assert(player.has_animation("open") and player.has_animation("close") and player.has_animation("opened"), "door authored clips missing")
	assert(is_equal_approx(player.get_animation("open").length, 0.28), "open timeline duration mismatch")
	assert(is_equal_approx(player.get_animation("close").length, 0.28), "close timeline duration mismatch")
	door.set_open(true)
	assert(player.current_animation == "open" and door.prompt == door.close_prompt, "open action must play and update prompt")
	player.advance(0.3)
	assert(is_equal_approx(sprite.rotation, -PI * 0.5), "open animation must rotate only the door leaf")
	assert(is_equal_approx(frame.rotation, 0.0), "door frame must remain stationary")
	door.set_open(false)
	assert(player.current_animation == "close" and door.prompt == door.open_prompt, "close action must play and update prompt")
	player.advance(0.3)
	assert(is_equal_approx(sprite.rotation, 0.0), "close animation must restore closed pose")
	door.is_open = true
	player.play("opened")
	player.advance(0.01)
	assert(is_equal_approx(sprite.rotation, -PI * 0.5), "restored open pose must be authored")
	print("DOOR AUTHORED PRESENTATION SMOKE: PASS (open/close timelines, prompt state, static frame and restored open pose)")
	get_tree().quit(0)
