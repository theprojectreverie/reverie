@tool
extends EditorScript
## Imports a complete authored Mossling animation set into one SpriteFrames resource.
## Artwork is supplied as one horizontal PNG strip per state and direction:
## res://assets/enemies/mossling/animations/<state>/<direction>.png
## Each frame is 96x128; strip width must equal frame_count * 96.
##
## This tool does not draw, generate, recolor, or alter artwork. It only slices
## authored PNG strips into AtlasTexture frames and writes SpriteFrames.

const ROOT := "res://assets/enemies/mossling/animations"
const OUTPUT := "res://assets/enemies/mossling/world_sheet.tres"
const FRAME_SIZE := Vector2i(96, 128)

# Animation names, counts, FPS and loop flags come from the runtime catalog.
# Do not maintain a second timing table here: the importer must track the same
# contract that SpriteFramesActorSource validates.


func _run() -> void:
	var errors: Array[String] = []
	var prepared: Dictionary = {}
	var total_frames := 0

	# Preflight every source before creating or overwriting the output resource.
	# The catalog is the single source of truth for all 9 states and 8 directions.
	for raw_state in CharacterAnimator.EXTENDED_STATES:
		var state := int(raw_state)
		var state_name := CharacterAnimator.state_name(state)
		var frame_count := CharacterAnimator.frame_count_for(state)
		total_frames += frame_count * CharacterAnimator.ALL_DIRECTIONS.size()
		for raw_direction in CharacterAnimator.ALL_DIRECTIONS:
			var direction_index := int(raw_direction)
			var direction := str(CharacterAnimationSpecCatalog.DIRECTION_NAMES[direction_index])
			var path := "%s/%s/%s.png" % [ROOT, state_name, direction]
			if not ResourceLoader.exists(path):
				errors.append("Missing: %s" % path)
				continue
			var texture := load(path) as Texture2D
			if texture == null:
				errors.append("Not a readable Texture2D: %s" % path)
				continue
			var expected := Vector2i(frame_count * FRAME_SIZE.x, FRAME_SIZE.y)
			var actual := Vector2i(texture.get_width(), texture.get_height())
			if actual != expected:
				errors.append("%s is %dx%d; expected %dx%d" % [
					path, actual.x, actual.y, expected.x, expected.y
				])
				continue
			var img := texture.get_image()
			if img == null or img.is_empty():
				errors.append("Image data unavailable: %s" % path)
				continue
			if img.get_pixel(0, 0).a > 0.02:
				errors.append("Top-left pixel is not transparent: %s" % path)
				continue
			var empty_frames: Array[int] = []
			var duplicate_frames: Array[String] = []
			var frame_signatures: Array[PackedByteArray] = []
			for frame_index in frame_count:
				var frame_region := img.get_region(Rect2i(
					frame_index * FRAME_SIZE.x, 0,
					FRAME_SIZE.x, FRAME_SIZE.y
				))
				if frame_region.get_used_rect().size == Vector2i.ZERO:
					empty_frames.append(frame_index)
				var signature := frame_region.get_data()
				for previous_index in frame_signatures.size():
					if frame_signatures[previous_index] == signature:
						duplicate_frames.append("%d duplicates %d" % [frame_index, previous_index])
						break
				frame_signatures.append(signature)
			if not empty_frames.is_empty():
				errors.append("%s contains fully transparent frame(s): %s" % [
					path, str(empty_frames)
				])
			if not duplicate_frames.is_empty():
				errors.append("%s contains exact duplicate frame(s): %s" % [
					path, ", ".join(duplicate_frames)
				])
			if not empty_frames.is_empty() or not duplicate_frames.is_empty():
				continue
			prepared["%s/%s" % [state_name, direction]] = texture

	if not errors.is_empty():
		push_error("Mossling import cancelled. No output was written.\n" + "\n".join(errors))
		print("Mossling preflight: %d issue(s); source art remains untouched." % errors.size())
		return

	var frames := SpriteFrames.new()
	if frames.has_animation(&"default"):
		frames.remove_animation(&"default")

	for raw_state in CharacterAnimator.EXTENDED_STATES:
		var state := int(raw_state)
		var state_name := CharacterAnimator.state_name(state)
		var frame_count := CharacterAnimator.frame_count_for(state)
		var animation_fps := CharacterAnimator.fps_for(state)
		var animation_loop := CharacterAnimator.looping_for(state)
		for raw_direction in CharacterAnimator.ALL_DIRECTIONS:
			var direction_index := int(raw_direction)
			var direction := str(CharacterAnimationSpecCatalog.DIRECTION_NAMES[direction_index])
			var animation_name := StringName("%s_%d" % [state_name, direction_index])
			frames.add_animation(animation_name)
			frames.set_animation_speed(animation_name, animation_fps)
			frames.set_animation_loop(animation_name, animation_loop)
			var atlas: Texture2D = prepared["%s/%s" % [state_name, direction]]
			for frame_index in frame_count:
				var region := AtlasTexture.new()
				region.atlas = atlas
				region.region = Rect2(
					frame_index * FRAME_SIZE.x, 0,
					FRAME_SIZE.x, FRAME_SIZE.y
				)
				frames.add_frame(animation_name, region)

	# Validate the assembled in-memory resource before touching the production
	# output. This catches importer regressions independently of source preflight.
	var build_errors: Array[String] = []
	var expected_animations := CharacterAnimator.EXTENDED_STATES.size() * CharacterAnimator.ALL_DIRECTIONS.size()
	if frames.get_animation_names().size() != expected_animations:
		build_errors.append("Built %d animations; expected exactly %d" % [
			frames.get_animation_names().size(), expected_animations
		])
	for raw_state in CharacterAnimator.EXTENDED_STATES:
		var state := int(raw_state)
		var state_name := CharacterAnimator.state_name(state)
		var expected_count := CharacterAnimator.frame_count_for(state)
		var expected_fps := CharacterAnimator.fps_for(state)
		var expected_loop := CharacterAnimator.looping_for(state)
		for raw_direction in CharacterAnimator.ALL_DIRECTIONS:
			var direction_index := int(raw_direction)
			var animation_name := StringName("%s_%d" % [state_name, direction_index])
			if not frames.has_animation(animation_name):
				build_errors.append("Built resource is missing %s" % animation_name)
				continue
			if frames.get_frame_count(animation_name) != expected_count:
				build_errors.append("%s has an unexpected frame count" % animation_name)
			if not is_equal_approx(frames.get_animation_speed(animation_name), expected_fps):
				build_errors.append("%s has an unexpected FPS value" % animation_name)
			if frames.get_animation_loop(animation_name) != expected_loop:
				build_errors.append("%s has an unexpected loop flag" % animation_name)
			for frame_index in frames.get_frame_count(animation_name):
				var frame_texture := frames.get_frame_texture(animation_name, frame_index)
				if frame_texture == null or frame_texture.get_width() != FRAME_SIZE.x or frame_texture.get_height() != FRAME_SIZE.y:
					build_errors.append("%s frame %d has invalid dimensions or texture" % [animation_name, frame_index])
	if not build_errors.is_empty():
		push_error("Mossling import cancelled after build validation. No output was written.\n" + "\n".join(build_errors))
		return

	var save_error := ResourceSaver.save(frames, OUTPUT)
	if save_error != OK:
		push_error("Mossling SpriteFrames save failed: %s" % error_string(save_error))
		return

	print("Mossling SpriteFrames imported successfully.")
	print("Animations: %d | Frames: %d | Output: %s" % [
		frames.get_animation_names().size(), total_frames, OUTPUT
	])
