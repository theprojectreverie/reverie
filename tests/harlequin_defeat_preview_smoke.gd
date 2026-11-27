extends SceneTree
func _initialize() -> void:
	call_deferred("run")
func run() -> void:
	var scene = load("res://assets/characters/harlequin/movement_preview.tscn").instantiate()
	root.add_child(scene)
	var player = scene.get_node("Player")
	var sprite = player.get_node("AnimatedSprite2D")
	var ok: bool = true
	for direction in [-1.0, 1.0]:
		player.set_combat_mode(true, direction)
		var pos: Vector2 = player.position
		player.play_hit()
		ok = ok and sprite.animation == &"hit" and sprite.flip_h == (direction > 0.0)
		await create_timer(0.8).timeout
		ok = ok and sprite.animation == &"combat_idle"
		player.play_defeat()
		ok = ok and sprite.animation == &"defeat" and sprite.flip_h == (direction > 0.0)
		await create_timer(1.1).timeout
		ok = ok and player.defeated and sprite.frame == 5 and not sprite.is_playing() and player.position.is_equal_approx(pos)
		player.start_attack(direction)
		ok = ok and sprite.animation == &"defeat"
		player.reset_defeat()
		ok = ok and sprite.animation == &"combat_idle"
	print("HARLEQUIN hit, defeat hold, mirror, reset=", ok)
	quit(0 if ok else 1)

