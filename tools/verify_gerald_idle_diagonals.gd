extends SceneTree
func _initialize() -> void:
	call_deferred("_verify")
func _verify() -> void:
	var frames := load("res://assets/characters/gerald/world_sheet.tres") as SpriteFrames
	if frames == null:
		push_error("GERALD_ANIMATION_VERIFY: failed to load")
		quit(1)
		return
	var ok := true
	for name in ["idle_0","idle_1","idle_2","idle_3","idle_4","idle_5","idle_6","idle_7"]:
		var n := frames.get_frame_count(StringName(name))
		var distinct := {}
		for i in range(n):
			var t := frames.get_frame_texture(StringName(name), i)
			if t != null:
				distinct[str(t.get_instance_id())] = true
		print("VERIFY ", name, " frames=", n, " unique=", distinct.size())
		if n != 5 or distinct.size() != 5: ok = false
	for name in ["walk_1","walk_3","walk_5","walk_7"]:
		var n := frames.get_frame_count(StringName(name))
		var distinct := {}
		for i in range(n):
			var t := frames.get_frame_texture(StringName(name), i)
			if t != null:
				distinct[str(t.get_instance_id())] = true
		print("VERIFY ", name, " frames=", n, " unique=", distinct.size())
		if n != 16 or distinct.size() < 8: ok = false
	print("GERALD_IDLE_DIAGONAL_VERIFY=", "PASS" if ok else "FAIL")
	quit(0 if ok else 1)
