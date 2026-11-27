extends SceneTree
var impacts: Array[Vector2] = []
var waves: Array[int] = []
func _initialize() -> void:
	call_deferred("run")
func run() -> void:
	var scene = load("res://assets/characters/harlequin/movement_preview.tscn").instantiate()
	root.add_child(scene)
	var player = scene.get_node("Player")
	var sprite = player.get_node("AnimatedSprite2D")
	player.ultimate_wave_impact.connect(func(target: Vector2, wave: int): impacts.append(target); waves.append(wave))
	var ok: bool = sprite.sprite_frames.get_frame_count(&"ultimate_cast") == 12
	for direction in [-1.0, 1.0]:
		var target: Vector2 = player.global_position + Vector2(direction * 200, -70)
		impacts.clear()
		waves.clear()
		player.start_ultimate(direction, target)
		ok = ok and sprite.animation == &"ultimate_cast" and sprite.flip_h == (direction > 0.0)
		await create_timer(2.4).timeout
		ok = ok and impacts.size() == 3 and waves == [0,1,2] and not player.ultimate_active and sprite.animation == &"combat_idle"
		for impact in impacts:
			ok = ok and impact.is_equal_approx(target)
		print("ULTIMATE direction=", direction, " waves=", waves, " pass=", ok)
	impacts.clear()
	player.start_ultimate(-1.0)
	await create_timer(0.65).timeout
	player.play_defeat()
	await create_timer(1.7).timeout
	ok = ok and impacts.is_empty() and not player.ultimate_active and player.defeated
	print("ULTIMATE cancellation=", impacts.is_empty(), " result=", ok)
	quit(0 if ok else 1)

