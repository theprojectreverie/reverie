extends SceneTree
var hits: Array[Vector2] = []
func _initialize() -> void:
	call_deferred("run")
func run() -> void:
	var scene = load("res://assets/characters/harlequin/movement_preview.tscn").instantiate()
	root.add_child(scene)
	var player = scene.get_node("Player")
	var sprite = player.get_node("AnimatedSprite2D")
	player.royal_impact.connect(func(target: Vector2): hits.append(target))
	var ok: bool = sprite.sprite_frames.get_frame_count(&"royal_cast") == 8
	for direction in [-1.0, 1.0]:
		hits.clear()
		var pos: Vector2 = player.global_position
		var target: Vector2 = pos + Vector2(direction * 200, -75)
		player.start_royal(direction, target)
		ok = ok and sprite.animation == &"royal_cast" and sprite.flip_h == (direction > 0.0)
		await create_timer(1.2).timeout
		ok = ok and hits.size() == 1 and not player.royal_active and sprite.animation == &"combat_idle" and player.global_position.is_equal_approx(pos)
		if hits.size() == 1:
			ok = ok and hits[0].is_equal_approx(target)
		print("ROYAL direction=", direction, " hits=", hits, " pass=", ok)
	hits.clear()
	player.start_royal(-1.0)
	await create_timer(0.15).timeout
	player.play_hit()
	await create_timer(1.1).timeout
	ok = ok and hits.is_empty() and not player.royal_active
	print("ROYAL cancellation=", hits.is_empty(), " result=", ok)
	quit(0 if ok else 1)

