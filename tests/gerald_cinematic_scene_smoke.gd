extends SceneTree

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	for script_path in [
		"res://scripts/ui/components/gerald_cinematic_sequence_component.gd",
		"res://scripts/ui/components/gerald_cinematic_presentation_component.gd",
		"res://scripts/ui/components/gerald_cinematic_playback_component.gd",
		"res://scripts/ui/components/gerald_cinematic_input_component.gd",
		"res://scripts/enemies/boss/gerald_boss_intro.gd",
		"res://scripts/ui/combat/combat_session_component.gd"
	]:
		var script_resource := load(script_path) as Script
		assert(script_resource != null, "Script failed to load: " + script_path)
	var packed: PackedScene = load("res://scenes/enemies/boss/gerald_boss_intro.tscn")
	assert(packed != null, "Gerald cinematic scene failed to load.")
	var intro: Control = packed.instantiate()
	get_root().add_child(intro)
	await process_frame
	var sequence: Node = intro.get_node("Sequence")
	assert(sequence.shots.size() == 17, "Fallen Guardian cinematic should contain seventeen shots.")
	for shot in sequence.shots:
		var image_path := str(shot.get("image", ""))
		var texture := load(image_path) as Texture2D
		assert(texture != null, "Cinematic image failed to load: " + image_path)
	assert(intro.get_node("Artwork").texture != null, "First Gerald story image was not displayed.")
	print("[GeraldCinematicSmoke] PASS: all 17 images load.")
	intro.queue_free()
	quit(0)
