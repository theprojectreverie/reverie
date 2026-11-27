extends SceneTree
func _initialize() -> void:
	call_deferred("run")
func run() -> void:
	var scene = load("res://assets/characters/harlequin/movement_preview.tscn").instantiate()
	root.add_child(scene)
	var player = scene.get_node("Player")
	var sprite = player.get_node("AnimatedSprite2D")
	var ok := true
	for pair in [["ui_left","nw"],["ui_right","ne"]]:
		var origin: Vector2 = player.position
		Input.action_press("ui_up")
		Input.action_press(pair[0])
		for i in range(15):
			await physics_frame
		var delta: Vector2 = player.position - origin
		var name: String = "walk_" + pair[1]
		var pass_dir: bool = sprite.animation == name and sprite.is_playing() and sprite.sprite_frames.get_frame_count(name) == 8 and delta.y < -10 and (delta.x < -10 if pair[1] == "nw" else delta.x > 10)
		print(name, " actual=", sprite.animation, " frame=", sprite.frame, " delta=", delta, " pass=", pass_dir)
		ok = ok and pass_dir
		Input.action_release("ui_up")
		Input.action_release(pair[0])
		for i in range(3):
			await physics_frame
		ok = ok and sprite.animation == "idle_" + pair[1]
	quit(0 if ok else 1)

