extends SceneTree
func _initialize() -> void:
	call_deferred("run")
func run() -> void:
	var scene = load("res://assets/characters/harlequin/movement_preview.tscn").instantiate()
	root.add_child(scene)
	var player = scene.get_node("Player")
	var sprite = player.get_node("AnimatedSprite2D")
	var ok: bool = true
	var cases = [[["ui_down"],"s"],[["ui_left"],"w"],[["ui_up"],"n"],[["ui_right"],"e"],[["ui_down","ui_left"],"sw"],[["ui_down","ui_right"],"se"],[["ui_up","ui_left"],"nw"],[["ui_up","ui_right"],"ne"]]
	for pair in cases:
		player.position = Vector2(640,360)
		for a in pair[0]:
			Input.action_press(a)
		Input.action_press("harlequin_preview_sprint")
		var origin: Vector2 = player.position
		for i in range(15):
			await physics_frame
		var distance: float = player.position.distance_to(origin)
		var good: bool = sprite.animation == "run_" + pair[1] and sprite.sprite_frames.get_frame_count(sprite.animation) == 8 and distance > 45.0
		ok = ok and good
		print("RUN ", pair[1], " distance=", distance, " pass=",good)
		Input.action_release("harlequin_preview_sprint")
		for i in range(3):
			await physics_frame
		ok = ok and sprite.animation == "walk_" + pair[1]
		for a in pair[0]:
			Input.action_release(a)
		for i in range(3):
			await physics_frame
		ok = ok and sprite.animation == "idle_" + pair[1]
	print("HARLEQUIN eight-direction sprint, walk, idle transitions=",ok)
	quit(0 if ok else 1)

