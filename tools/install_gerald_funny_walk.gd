extends SceneTree

const PROJECT_SHEET := "res://assets/characters/gerald/world_sheet.tres"
const FRAME_ROOT := "res://assets/characters/gerald/generated/gerald_walk_4dir_16x128/"
const DIRECTIONS := {
	"front": 0,
	"right": 2,
	"back": 4,
	"left": 6,
}

func _initialize() -> void:
	call_deferred("_install")

func _install() -> void:
	var frames := load(PROJECT_SHEET) as SpriteFrames
	if frames == null:
		push_error("GERALD_WALK_INSTALL: could not load world_sheet.tres")
		quit(1)
		return
	var installed := 0
	for direction_name in DIRECTIONS:
		var direction_index := int(DIRECTIONS[direction_name])
		var animation_name := StringName("walk_%d" % direction_index)
		if frames.has_animation(animation_name):
			frames.remove_animation(animation_name)
		frames.add_animation(animation_name)
		frames.set_animation_speed(animation_name, 12.0)
		frames.set_animation_loop(animation_name, true)
		for frame_index in range(1, 17):
			var frame_path := FRAME_ROOT + "%s_%02d.png" % [direction_name, frame_index]
			if not FileAccess.file_exists(frame_path):
				push_error("GERALD_WALK_INSTALL: missing " + frame_path)
				quit(1)
				return
			var texture := load(frame_path) as Texture2D
			if texture == null or texture.get_width() != 128 or texture.get_height() != 128:
				push_error("GERALD_WALK_INSTALL: invalid 128x128 texture " + frame_path)
				quit(1)
				return
			frames.add_frame(animation_name, texture)
			installed += 1
		if frames.get_frame_count(animation_name) != 16:
			push_error("GERALD_WALK_INSTALL: incorrect frame count for " + String(animation_name))
			quit(1)
			return
	var save_error := ResourceSaver.save(frames, PROJECT_SHEET)
	if save_error != OK:
		push_error("GERALD_WALK_INSTALL: ResourceSaver failed with code %d" % save_error)
		quit(1)
		return
	print("GERALD_WALK_INSTALL_OK frames=", installed, " animations=walk_0,walk_2,walk_4,walk_6")
	print("GERALD_WALK_INSTALL_PRESERVED_DIAGONALS=", frames.has_animation("walk_1") and frames.has_animation("walk_3") and frames.has_animation("walk_5") and frames.has_animation("walk_7"))
	print("GERALD_WALK_INSTALL_TOTAL_ANIMATIONS=", frames.get_animation_names().size())
	quit(0)
