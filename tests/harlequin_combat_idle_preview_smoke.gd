extends SceneTree
func _initialize() -> void:
	call_deferred("run")
func run() -> void:
	var scene = load("res://assets/characters/harlequin/movement_preview.tscn").instantiate()
	root.add_child(scene)
	var player = scene.get_node("Player")
	var sprite = player.get_node("AnimatedSprite2D")
	var ok: bool = sprite.sprite_frames.get_frame_count(&"combat_idle") == 6 and sprite.sprite_frames.get_animation_loop(&"combat_idle")
	for direction in [-1.0, 1.0]:
		player.set_combat_mode(true, direction)
		ok = ok and sprite.animation == &"combat_idle" and sprite.flip_h == (direction > 0.0)
		await create_timer(0.5).timeout
		ok = ok and sprite.is_playing() and sprite.frame > 0
		var pos: Vector2 = player.position
		player.start_attack(direction)
		await create_timer(1.0).timeout
		ok = ok and sprite.animation == &"combat_idle" and sprite.flip_h == (direction > 0.0) and player.position.is_equal_approx(pos)
	player.set_combat_mode(false)
	ok = ok and sprite.animation == &"idle_s" and not sprite.flip_h
	print("HARLEQUIN combat idle loop, mirroring, attack recovery and exploration restore=", ok)
	quit(0 if ok else 1)

