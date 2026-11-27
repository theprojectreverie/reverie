extends SceneTree
func _initialize() -> void:
	call_deferred("_run")
func _run() -> void:
	var scene = load("res://scenes/characters/actor_visual.tscn").instantiate()
	root.add_child(scene)
	await process_frame
	var report: Dictionary = scene.configure_character("kael")
	var ok: bool = report.get("registered", false)
	for d in range(8):
		scene.play(1, d)
		scene.play(0, d)
		var seen := {}
		var matching := true
		for i in range(7):
			scene.play(0, d)
			scene.tick_animation(0.17)
			var tex = scene.get_node("FrameSprite").texture
			if tex is AtlasTexture:
				seen[tex.region.position.x] = true
				matching = matching and tex.atlas.resource_path.contains("kael_idle_")
			else:
				matching = false
		var pass_dir: bool = seen.size() == 5 and matching and scene.animator.direction == d
		ok = ok and pass_dir
		print("KAEL idle direction=",d," visible frames=",seen.size()," pass=",pass_dir)
	scene.queue_free()
	await process_frame
	print("KAEL IDLE PLAYBACK: ",ok)
	quit(0 if ok else 1)

