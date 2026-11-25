extends SceneTree

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var touch := root.get_node_or_null("TouchInput")
	if touch == null:
		push_error("MOBILE_HUD_TOUCH_AUTOLOAD_MISSING")
		quit(1)
		return
	touch.set("using_touch", true)
	var packed := load("res://scenes/ui/hud.tscn") as PackedScene
	if packed == null:
		push_error("MOBILE_HUD_SCENE_MISSING")
		quit(1)
		return
	var hud := packed.instantiate() as Control
	root.add_child(hud)
	await process_frame
	await process_frame
	var joystick := hud.get_node_or_null("Joystick") as Control
	var interact := hud.get_node_or_null("TouchInteractButton") as Button
	var switch_button := hud.get_node_or_null("TouchSwitchButton") as Button
	var ok := joystick != null and joystick.visible and interact != null and switch_button != null and switch_button.visible
	print("MOBILE_HUD_JOYSTICK_VISIBLE=", joystick.visible if joystick != null else false)
	print("MOBILE_HUD_SWITCH_VISIBLE=", switch_button.visible if switch_button != null else false)
	print("MOBILE_HUD_INTERACT_PROMPT_GATED=", interact != null and not interact.visible)
	print("MOBILE_HUD_CONTROLS_READY=", ok)
	hud.queue_free()
	quit(0 if ok else 1)
