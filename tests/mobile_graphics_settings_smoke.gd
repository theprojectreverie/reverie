extends Node

func _ready() -> void:
	call_deferred("_run")

func _run() -> void:
	var old_quality: int = GraphicsSettings.quality
	var light := preload("res://scenes/world/castle_gardens/components/castle_garden_light.tscn").instantiate() as PointLight2D
	add_child(light)
	light.position = Vector2(100, 100)
	var essential := PointLight2D.new()
	add_child(essential)
	var old_fps: int = GraphicsSettings.frame_limit
	var ambient := preload("res://scenes/ui/combat/components/combat_ambient_particles.tscn").instantiate()
	add_child(ambient)
	await get_tree().process_frame
	var particles := ambient.get_node("VioletEmbers") as CPUParticles2D
	var original: int = int(particles.get_meta("graphics_original_amount", particles.amount))
	GraphicsSettings.apply_preferences(0, 0)
	assert(Engine.max_fps == 30)
	assert(get_tree().root.content_scale_mode == Window.CONTENT_SCALE_MODE_VIEWPORT)
	assert(not particles.emitting)
	assert(GraphicsSettings.ambient_multiplier() == 0.0)
	assert(not light.visible and essential.visible)
	assert(GraphicsSettings.atmosphere_refresh_interval() == 0.75)
	var late_ambient := preload("res://scenes/world/castle_gardens/components/castle_garden_ambient_particles.tscn").instantiate()
	add_child(late_ambient)
	await get_tree().process_frame
	for n in get_tree().get_nodes_in_group(GraphicsSettings.AMBIENT_GROUP):
		assert(not n.emitting)
	GraphicsSettings.apply_preferences(1, 45)
	assert(Engine.max_fps == 45)
	assert(GraphicsSettings.ambient_multiplier() == 0.5)
	assert(GraphicsSettings.atmosphere_refresh_interval() == 0.5)
	assert(light.visible)
	light.position = Vector2(100000, 100000)
	await get_tree().create_timer(0.25).timeout
	assert(not light.visible)
	light.position = Vector2(100, 100)
	await get_tree().create_timer(0.25).timeout
	assert(light.visible)
	assert(particles.emitting and particles.amount == ceili(original * 0.5))
	GraphicsSettings.apply_preferences(2, -1)
	assert(Engine.max_fps == 0)
	assert(light.visible and essential.visible)
	assert(GraphicsSettings.atmosphere_refresh_interval() == 0.25)
	assert(get_tree().root.content_scale_mode == Window.CONTENT_SCALE_MODE_CANVAS_ITEMS)
	assert(particles.emitting and particles.amount == original)
	assert(GraphicsSettings.normalize_fps(999) == 0)
	GraphicsSettings.apply_preferences(2, 60, true, true)
	assert(GraphicsSettings._monitor != null)
	assert("FPS" in GraphicsSettings._monitor.get_node("Panel/Readout").text)
	for i in range(GraphicsSettings.ADAPT_WARMUP):
		GraphicsSettings._sample_performance(15.0, true)
	assert(GraphicsSettings.quality == 2)
	for i in range(GraphicsSettings.LOW_FPS_SAMPLES - 1):
		GraphicsSettings._sample_performance(15.0, true)
	GraphicsSettings._sample_performance(15.0, false)
	assert(GraphicsSettings.quality == 2)
	for i in range(GraphicsSettings.LOW_FPS_SAMPLES):
		GraphicsSettings._sample_performance(15.0, true)
	assert(GraphicsSettings.quality == 1 and GraphicsSettings.requested_quality == 2)
	GraphicsSettings.apply_preferences(2, 60, true, false)
	assert(GraphicsSettings.quality == 1 and GraphicsSettings._monitor == null)
	for i in range(GraphicsSettings.ADAPT_WARMUP + GraphicsSettings.LOW_FPS_SAMPLES):
		GraphicsSettings._sample_performance(15.0, true)
	assert(GraphicsSettings.quality == 0 and Engine.max_fps == 60)
	for i in range(50):
		GraphicsSettings._sample_performance(60.0, true)
	assert(GraphicsSettings.quality == 0)
	GraphicsSettings.apply_preferences(2, 30, true, false)
	for i in range(GraphicsSettings.ADAPT_WARMUP + GraphicsSettings.LOW_FPS_SAMPLES):
		GraphicsSettings._sample_performance(30.0, true)
	assert(GraphicsSettings.quality == 2 and Engine.max_fps == 30)
	GraphicsSettings.apply_preferences(2, 60, false, false)
	assert(not GraphicsSettings.adaptive_enabled and GraphicsSettings.quality == 2)
	assert(GraphicsSettings.lifecycle_frame_cap(120, true, true, false) == 120)
	assert(GraphicsSettings.lifecycle_frame_cap(120, true, false, false) == 30)
	assert(GraphicsSettings.lifecycle_frame_cap(0, true, false, true) == 15)
	assert(GraphicsSettings.lifecycle_frame_cap(10, true, false, true) == 10)
	assert(GraphicsSettings.lifecycle_frame_cap(120, false, false, true) == 120)
	GraphicsSettings._notification(NOTIFICATION_APPLICATION_FOCUS_OUT)
	GraphicsSettings._notification(NOTIFICATION_APPLICATION_PAUSED)
	GraphicsSettings._notification(NOTIFICATION_APPLICATION_FOCUS_IN)
	assert(not GraphicsSettings._app_active)
	GraphicsSettings._notification(NOTIFICATION_APPLICATION_RESUMED)
	assert(GraphicsSettings._app_active)
	var burst := preload("res://scenes/ui/combat/components/elemental_burst.tscn").instantiate() as CPUParticles2D
	add_child(burst)
	assert(burst.amount == 14)
	GraphicsSettings.apply_preferences(0, 30)
	GraphicsSettings.prepare_combat_particles(burst)
	assert(burst.amount == 6)
	GraphicsSettings.prepare_combat_particles(burst)
	assert(burst.amount == 6)
	GraphicsSettings.apply_preferences(1, 60)
	GraphicsSettings.prepare_combat_particles(burst)
	assert(burst.amount == 10)
	GraphicsSettings.apply_preferences(2, 60)
	GraphicsSettings.prepare_combat_particles(burst)
	assert(burst.amount == 14)
	burst.queue_free()
	var panel := preload("res://scenes/ui/settings_screen.tscn").instantiate() as SettingsScreen
	add_child(panel)
	await get_tree().process_frame
	assert(panel._quality_option.item_count == 3)
	assert(panel._fps_option.item_count == 7)
	panel._quality_option.select(0)
	panel._fps_option.select(2)
	panel._adaptive_check.button_pressed = true
	panel._monitor_check.button_pressed = true
	var staged := panel._collect_working_from_ui()
	assert(staged.adaptive_graphics and staged.performance_monitor)
	assert(staged.graphics_quality == 0 and staged.fps_limit == 45)
	var test_path := "user://mobile_graphics_smoke_%d.cfg" % OS.get_process_id()
	panel._persistence_component.save_config(staged, test_path)
	var restored: Dictionary = panel._persistence_component.load_config(test_path)
	assert(restored.graphics_quality == 0 and restored.fps_limit == 45)
	assert(restored.adaptive_graphics and restored.performance_monitor)
	DirAccess.remove_absolute(test_path)
	panel._set_columns_for_width(800)
	assert(panel._columns_layout.columns == 1)
	panel._set_columns_for_width(1280)
	assert(panel._columns_layout.columns == (1 if OS.has_feature("mobile") else 2))
	panel._restore_defaults()
	assert(panel._quality_option.selected == GraphicsSettings.default_quality())
	assert(not panel._adaptive_check.button_pressed and not panel._monitor_check.button_pressed)
	panel.close_screen()
	await get_tree().process_frame
	SettingsScreen.clear_project_default_input_cache()
	light.queue_free()
	essential.queue_free()
	ambient.queue_free()
	late_ambient.queue_free()
	await get_tree().process_frame
	GraphicsSettings.apply_preferences(old_quality, old_fps)
	AudioDirector.stop_all_audio_immediately()
	await get_tree().create_timer(0.5).timeout
	print("MOBILE_GRAPHICS_SMOKE_PASS")
	get_tree().quit(0)
