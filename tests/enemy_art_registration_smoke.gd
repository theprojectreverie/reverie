extends SceneTree

const SOURCE_SCRIPT := preload("res://scripts/art/sprite_frames_actor_source.gd")

func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var source: ActorFrameSource = SOURCE_SCRIPT.from_enemy("mossling")
	if source == null:
		_fail("from_enemy returned null")
		return
	if source.has_frames():
		_fail("Mossling unexpectedly reports frames without a production SpriteFrames resource")
		return
	if not source.is_temporary():
		_fail("Missing Mossling source must remain temporary")
		return
	var errors := source.validate_sheets()
	if errors.is_empty():
		_fail("Missing Mossling source must report validation errors")
		return
	var report: Dictionary = SOURCE_SCRIPT.enemy_validation_report("mossling")
	if str(report.get("expected_tres", "")) != "res://assets/enemies/mossling/world_sheet.tres":
		_fail("Enemy report does not point at the dedicated Mossling enemy art folder")
		return
	if bool(report.get("registered", true)):
		_fail("Incomplete Mossling art must not register")
		return
	if not bool(report.get("fallback_active", false)):
		_fail("Incomplete Mossling art must retain fallback")
		return
	var playable: ActorFrameSource = SOURCE_SCRIPT.register_playable("mossling")
	if playable == null:
		_fail("Playable registration path returned null")
		return
	if playable.sheet_path.begins_with("res://assets/enemies/"):
		_fail("Playable lookup incorrectly resolved through enemy art")
		return
	if not _test_validator_contract():
		return
	print("PASS: enemy art lookup isolation, fallback retention, exact 72-animation count, FPS validation and production frame contract")
	quit(0)


func _test_validator_contract() -> bool:
	# Synthetic textures exist only inside this test; they are never saved or
	# registered as artwork. This isolates validation logic from art availability.
	var image := Image.create(96, 128, false, Image.FORMAT_RGBA8)
	image.fill(Color.TRANSPARENT)
	var texture := ImageTexture.create_from_image(image)
	var frames := SpriteFrames.new()
	if frames.has_animation(&"default"):
		frames.remove_animation(&"default")
	for raw_state in CharacterAnimator.EXTENDED_STATES:
		var state := int(raw_state)
		var animation_frames := CharacterAnimator.frame_count_for(state)
		var animation_fps := CharacterAnimator.fps_for(state)
		var looping := CharacterAnimator.looping_for(state)
		for raw_direction in CharacterAnimator.ALL_DIRECTIONS:
			var direction := int(raw_direction)
			var animation := StringName("%s_%d" % [CharacterAnimator.state_name(state), direction])
			frames.add_animation(animation)
			frames.set_animation_speed(animation, animation_fps)
			frames.set_animation_loop(animation, looping)
			for frame_index in animation_frames:
				frames.add_frame(animation, texture)
	var probe: ActorFrameSource = load("res://scripts/art/sprite_frames_actor_source.gd").new("validator_probe")
	probe.sprite_frames = frames
	probe.loaded_from_disk = false
	var valid_errors := probe.validate_sheets()
	if not valid_errors.is_empty():
		_fail("A synthetic sheet matching the authoritative catalog was rejected: %s" % str(valid_errors.slice(0, 4)))
		return false
	if not probe.has_frames():
		_fail("A complete validated 72-animation sheet must expose frames")
		return false
	# Exercise the runtime lookup contract independently of whole-sheet QA.
	var directional_frame := probe.frame(CharacterAnimator.State.WALK, CharacterAnimator.Direction.DOWN_LEFT, 15)
	if directional_frame == null or directional_frame.get_width() != 96 or directional_frame.get_height() != 128:
		_fail("Directional frame lookup must return the requested 96x128 texture")
		return false
	if probe.frame(CharacterAnimator.State.WALK, CharacterAnimator.Direction.DOWN_LEFT, 999) == null:
		_fail("Out-of-range frame indices should clamp to the last valid frame")
		return false
	if probe.frame(999, CharacterAnimator.Direction.DOWN_LEFT, 0) != null:
		_fail("Invalid state IDs must never resolve a production texture")
		return false
	if probe.frame_count(CharacterAnimator.State.WALK, CharacterAnimator.Direction.DOWN_LEFT) != 16:
		_fail("Directional frame count must match the authoritative animation contract")
		return false
	if not is_equal_approx(probe.fps(CharacterAnimator.State.WALK), 12.0) or not probe.is_looping(CharacterAnimator.State.WALK):
		_fail("Frame source timing metadata must match the authoritative walk contract")
		return false
	frames.set_animation_speed(&"walk_0", 99.0)
	var fps_errors := probe.validate_sheets()
	var found_fps_error := false
	for error in fps_errors:
		if str(error).contains("walk_0") and str(error).contains("FPS"):
			found_fps_error = true
	if not found_fps_error:
		_fail("Validator did not reject an incorrect animation FPS")
		return false
	frames.set_animation_speed(&"walk_0", CharacterAnimator.fps_for(1))

	# Wrong loop metadata must be rejected independently of frame rate.
	frames.set_animation_loop(&"walk_0", false)
	var loop_errors := probe.validate_sheets()
	var found_loop_error := false
	for error in loop_errors:
		if str(error).contains("walk_0") and str(error).contains("loop="):
			found_loop_error = true
	if not found_loop_error:
		_fail("Validator did not reject an incorrect animation loop flag")
		return false
	frames.set_animation_loop(&"walk_0", CharacterAnimator.looping_for(1))

	# A shortened strip must fail even when its remaining frames are valid.
	frames.remove_frame(&"walk_0", frames.get_frame_count(&"walk_0") - 1)
	var frame_count_errors := probe.validate_sheets()
	var found_frame_count_error := false
	for error in frame_count_errors:
		if str(error).contains("walk_0") and str(error).contains("frames, expected"):
			found_frame_count_error = true
	if not found_frame_count_error:
		_fail("Validator did not reject an incorrect per-animation frame count")
		return false
	frames.add_frame(&"walk_0", texture)

	# Texture dimensions are checked on every frame, not just the first.
	var wrong_size_image := Image.create(32, 32, false, Image.FORMAT_RGBA8)
	wrong_size_image.fill(Color.TRANSPARENT)
	var wrong_size_texture := ImageTexture.create_from_image(wrong_size_image)
	frames.set_frame(&"walk_0", 3, wrong_size_texture)
	var dimension_errors := probe.validate_sheets()
	var found_dimension_error := false
	for error in dimension_errors:
		if str(error).contains("walk_0") and str(error).contains("32x32"):
			found_dimension_error = true
	if not found_dimension_error:
		_fail("Validator did not reject a frame with incorrect canvas dimensions")
		return false
	frames.set_frame(&"walk_0", 3, texture)

	# A null frame texture must be rejected instead of passing as a valid slot.
	frames.set_frame(&"walk_0", 4, null)
	if probe.frame(CharacterAnimator.State.WALK, CharacterAnimator.Direction.DOWN, 4) != null:
		_fail("A null directional frame slot must return null so the renderer can fall back safely")
		return false
	var null_texture_errors := probe.validate_sheets()
	var found_null_texture_error := false
	for error in null_texture_errors:
		if str(error).contains("walk_0") and str(error).contains("frame 4 is null"):
			found_null_texture_error = true
	if not found_null_texture_error:
		_fail("Validator did not reject a null frame texture")
		return false
	frames.set_frame(&"walk_0", 4, texture)

	# Missing directional/state animation must be reported by name.
	frames.remove_animation(&"walk_0")
	var missing_animation_errors := probe.validate_sheets()
	var found_missing_animation_error := false
	for error in missing_animation_errors:
		if str(error).contains("missing animation 'walk_0'"):
			found_missing_animation_error = true
	if not found_missing_animation_error:
		_fail("Validator did not identify a missing required animation")
		return false
	if probe.has_frames():
		_fail("A partial sheet must not expose frames or replace the procedural fallback")
		return false
	# Recreate it so the following exact-count check isolates the extra entry.
	frames.add_animation(&"walk_0")
	frames.set_animation_speed(&"walk_0", CharacterAnimator.fps_for(1))
	frames.set_animation_loop(&"walk_0", CharacterAnimator.looping_for(1))
	for frame_index in CharacterAnimator.frame_count_for(1):
		frames.add_frame(&"walk_0", texture)

	frames.add_animation(&"unexpected_extra")
	var count_errors := probe.validate_sheets()
	var found_count_error := false
	for error in count_errors:
		if str(error).contains("expected exactly 72"):
			found_count_error = true
	if not found_count_error:
		_fail("Validator did not reject an extra animation beyond the exact 72")
		return false
	return true


func _fail(message: String) -> void:
	push_error("FAIL: " + message)
	quit(1)
