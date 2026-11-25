extends SceneTree

func _initialize() -> void:
	call_deferred("_verify")

func _verify() -> void:
	var packed := load("res://scenes/characters/actor_visual.tscn") as PackedScene
	if packed == null:
		push_error("GERALD_RUNTIME_TEST_SCENE_MISSING")
		quit(1)
		return
	var visual := packed.instantiate() as ActorVisual
	root.add_child(visual)
	await process_frame
	visual.setup({"skin": "#d5a28a", "primary": "#3b2635", "secondary": "#e6a12e", "hair": "#241b25", "accent": "#ff6a2e"}, ActorVisual.Kind.HUMAN, "gerald", "Human", "fire")
	var report := visual.configure_character("gerald")
	print("GERALD_ACTOR_REGISTERED=", report.get("registered", false))
	print("GERALD_ACTOR_SOURCE=", report.get("source", ""))
	var expected := {0: "front", 2: "right", 4: "back", 6: "left"}
	var ok := bool(report.get("registered", false))
	for direction in expected:
		visual.play(1, int(direction))
		visual.animator.tick(1.0 / 12.0)
		visual._update_sprite_frame()
		var texture: Texture2D = visual._sprite.texture if visual._sprite != null else null
		var expected_prefix := "%s_" % str(expected[direction])
		var actual_name := texture.resource_path.get_file() if texture != null else ""
		var texture_matches := actual_name.begins_with(expected_prefix)
		print("GERALD_DIRECTION_", direction, "_FRAME=", visual.animator.frame, " TEXTURE_MATCH=", texture_matches, " TEXTURE=", actual_name)
		if texture == null or not texture_matches or not visual._sprite.visible:
			ok = false
	print("GERALD_RUNTIME_WALK_DIRECTIONS_PASS=", ok)
	visual.queue_free()
	await process_frame
	quit(0 if ok else 1)
