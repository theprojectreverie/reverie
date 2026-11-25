extends SceneTree

func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var packed := load("res://scenes/world/components/terrain/water_surface.tscn") as PackedScene
	if packed == null:
		push_error("Water surface scene failed to load")
		quit(1)
		return
	var surface := packed.instantiate() as WaterSurfaceComponent
	root.add_child(surface)
	await process_frame
	var player := surface.get_node("AnimationPlayer") as AnimationPlayer
	var ripple_a := surface.get_node("RippleA") as Line2D
	var ripple_b := surface.get_node("RippleB") as Line2D
	if not player.is_playing() or player.current_animation != &"ripple":
		push_error("Authored water ripple did not autoplay")
		quit(1)
		return
	if ripple_a.points.size() < 8 or ripple_b.points.size() < 8:
		push_error("Authored ripple geometry is incomplete")
		quit(1)
		return
	var start_scale := ripple_a.scale
	await create_timer(0.7).timeout
	if ripple_a.scale.is_equal_approx(start_scale):
		push_error("Ripple animation did not advance")
		quit(1)
		return
	surface.set_ripple_enabled(false)
	if player.is_playing() or ripple_a.visible or ripple_b.visible:
		push_error("Ripple animation or geometry did not hide when disabled")
		quit(1)
		return
	surface.set_ripple_enabled(true)
	if not player.is_playing() or not ripple_a.visible or not ripple_b.visible:
		push_error("Ripple animation did not restore after re-enabling")
		quit(1)
		return
	surface.set_flow_speed(1.25)
	if not is_equal_approx(player.speed_scale, 1.25):
		push_error("Runtime flow speed was not applied")
		quit(1)
		return
	surface.set_wave_amplitude(2.0)
	if not is_equal_approx(ripple_a.width, 4.0) or not is_equal_approx(ripple_b.width, 3.0):
		push_error("Wave amplitude did not update authored ripple line widths")
		quit(1)
		return
	print("WORLD WATER SURFACE SMOKE: PASS (authored ripple, disable/re-enable, runtime flow speed and amplitude)")
	quit(0)
