extends SceneTree

const SHEET := "res://assets/characters/gerald/world_sheet.tres"
const IDLE_SOURCE := "res://assets/characters/gerald/generated/gerald_idle_8dir_8f_96x128.png"

func _initialize() -> void:
	call_deferred("_install")

func _install() -> void:
	var frames := load(SHEET) as SpriteFrames
	var atlas := load(IDLE_SOURCE) as Texture2D
	if frames == null or atlas == null:
		push_error("GERALD_IDLE_INSTALL: missing SpriteFrames or idle atlas")
		quit(1)
		return
	if atlas.get_width() != 768 or atlas.get_height() != 1024:
		push_error("GERALD_IDLE_INSTALL: expected 768x1024, got %dx%d" % [atlas.get_width(), atlas.get_height()])
		quit(1)
		return
	var count := 0
	for direction in range(8):
		var animation := StringName("idle_%d" % direction)
		if not frames.has_animation(animation):
			push_error("GERALD_IDLE_INSTALL: missing " + String(animation))
			quit(1)
			return
		frames.clear(animation)
		frames.set_animation_speed(animation, 9.0)
		frames.set_animation_loop(animation, true)
		for column in range(8):
			var frame := AtlasTexture.new()
			frame.atlas = atlas
			frame.region = Rect2(column * 96, direction * 128, 96, 128)
			frames.add_frame(animation, frame)
			count += 1
		if frames.get_frame_count(animation) != 8:
			push_error("GERALD_IDLE_INSTALL: bad frame count for " + String(animation))
			quit(1)
			return
	var err := ResourceSaver.save(frames, SHEET)
	if err != OK:
		push_error("GERALD_IDLE_INSTALL: save failed %d" % err)
		quit(1)
		return
	print("GERALD_IDLE_INSTALL_OK frames=", count, " animations=idle_0..idle_7 source=8x8 atlas")
	quit(0)
