extends SceneTree

var releases: Array[Vector2] = []
var directions: Array[Vector2] = []

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	var scene = load("res://assets/characters/harlequin/movement_preview.tscn").instantiate()
	root.add_child(scene)
	var player = scene.get_node("Player")
	var sprite = player.get_node("AnimatedSprite2D")
	player.card_released.connect(func(origin: Vector2, direction: Vector2): releases.append(origin); directions.append(direction))
	var ok := true
	for sign_value in [-1.0, 1.0]:
		var origin: Vector2 = player.global_position
		player.start_attack(sign_value)
		ok = ok and sprite.animation == &"attack_card" and sprite.flip_h == (sign_value > 0.0) and sprite.sprite_frames.get_frame_count(&"attack_card") == 8
		await create_timer(1.0).timeout
		ok = ok and not player.attacking and not sprite.flip_h and player.global_position.is_equal_approx(origin)
		if releases.size() > 0:
			ok = ok and is_equal_approx(releases.back().x - origin.x, sign_value * 39.0) and directions.back().x == sign_value
	ok = ok and releases.size() == 2
	print("HARLEQUIN mirrored attack=", ok, " releases=", releases, " directions=", directions)
	quit(0 if ok else 1)

