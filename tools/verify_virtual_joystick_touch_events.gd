extends SceneTree

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var touch := root.get_node_or_null("TouchInput")
	if touch == null:
		push_error("TOUCH_INPUT_AUTOLOAD_MISSING")
		quit(1)
		return
	var joystick_scene := load("res://scenes/ui/virtual_joystick.tscn") as PackedScene
	if joystick_scene == null:
		push_error("VIRTUAL_JOYSTICK_SCENE_MISSING")
		quit(1)
		return
	var joystick := joystick_scene.instantiate() as Control
	root.add_child(joystick)
	joystick.size = Vector2(170, 170)
	await process_frame
	var start := InputEventScreenTouch.new()
	start.index = 3
	start.pressed = true
	start.position = Vector2(155, 85)
	joystick.call("_gui_input", start)
	var right_value: Vector2 = touch.get("move_vector")
	var right_active: bool = touch.get("touch_active")
	print("JOYSTICK_TOUCH_RIGHT vector=", right_value, " active=", right_active)
	if not right_active or right_value.x < 0.95 or absf(right_value.y) > 0.05:
		push_error("JOYSTICK_TOUCH_START_DID_NOT_REGISTER")
		joystick.queue_free()
		quit(1)
		return
	var drag := InputEventScreenDrag.new()
	drag.index = 3
	drag.position = Vector2(85, 15)
	joystick.call("_gui_input", drag)
	var up_value: Vector2 = touch.get("move_vector")
	print("JOYSTICK_TOUCH_DRAG_UP vector=", up_value)
	if up_value.y > -0.95 or absf(up_value.x) > 0.05:
		push_error("JOYSTICK_TOUCH_DRAG_DID_NOT_UPDATE")
		joystick.queue_free()
		quit(1)
		return
	var release := InputEventScreenTouch.new()
	release.index = 3
	release.pressed = false
	release.position = Vector2(85, 15)
	joystick.call("_gui_input", release)
	var released: bool = not bool(touch.get("touch_active")) and touch.get("move_vector") == Vector2.ZERO
	print("JOYSTICK_TOUCH_RELEASE_CLEARS_INPUT=", released)
	joystick.queue_free()
	quit(0 if released else 1)
