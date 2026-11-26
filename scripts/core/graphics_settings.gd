extends Node
## Device-local rendering preferences. Never changes physics, networking or combat logic.
signal quality_changed

const CONFIG_PATH := "user://settings.cfg"
const SECTION := "graphics"
const QUALITY_NAMES := ["Battery Saver", "Balanced", "High"]
const FPS_OPTIONS := [0, 30, 45, 60, 90, 120, -1]
const MONITOR_SCENE := preload("res://scenes/ui/components/performance_monitor.tscn")
const LOW_FPS_SAMPLES := 8
const ADAPT_WARMUP := 12
var requested_quality: int = 2
var adaptive_enabled := false
var monitor_enabled := false
var _monitor: CanvasLayer
var _sample_elapsed := 0.0
var _low_samples := 0
var _warmup := ADAPT_WARMUP
var _sample_scene_id := 0
var _app_active := true
var _app_focused := true
var _app_paused := false
var _ready_for_lifecycle := false
const AMBIENT_GROUP := "optional_ambient_fx"
const LIGHT_GROUP := "optional_environment_light"
const LIGHT_CULL_INTERVAL := 0.15
const LIGHT_CULL_MARGIN := 256.0
var _light_elapsed: float = 0.0
var quality: int = 2
var frame_limit: int = 0

func default_quality() -> int:
	return 0 if OS.has_feature("mobile") else 2

func normalize_quality(value: Variant) -> int:
	return clampi(int(value), 0, QUALITY_NAMES.size() - 1) if value is int else default_quality()

func normalize_fps(value: Variant) -> int:
	return int(value) if value is int and FPS_OPTIONS.has(value) else 0

func _ready() -> void:
	var cfg := ConfigFile.new()
	cfg.load(CONFIG_PATH)
	apply_preferences(cfg.get_value(SECTION, "quality", default_quality()), cfg.get_value(SECTION, "fps", 0), cfg.get_value(SECTION, "adaptive", false), cfg.get_value(SECTION, "monitor", false))
	get_tree().node_added.connect(_on_node_added)
	process_mode = Node.PROCESS_MODE_ALWAYS
	_ready_for_lifecycle = true
	_update_processing()
	_refresh_frame_cap()

func apply_preferences(preset: Variant, fps: Variant, adaptive: bool = false, monitor: bool = false) -> void:
	var next_quality := normalize_quality(preset)
	var next_fps := normalize_fps(fps)
	var reset_quality := next_quality != requested_quality or next_fps != frame_limit or adaptive != adaptive_enabled or not adaptive
	requested_quality = next_quality
	frame_limit = next_fps
	adaptive_enabled = adaptive
	monitor_enabled = monitor
	if reset_quality:
		_low_samples = 0
		_warmup = ADAPT_WARMUP
		_apply_quality(requested_quality)
	else:
		_update_processing()
	_update_monitor()


func _apply_quality(preset: int) -> void:
	var previous_quality := quality
	quality = preset
	_refresh_frame_cap()
	var window := get_tree().root
	# Keep logical layout and touch coordinates unchanged. On reduced modes
	# render the 2D canvas at the project's base viewport instead of native pixels.
	window.content_scale_mode = Window.CONTENT_SCALE_MODE_CANVAS_ITEMS if quality == 2 else Window.CONTENT_SCALE_MODE_VIEWPORT
	for node in get_tree().get_nodes_in_group(AMBIENT_GROUP):
		_apply_ambient(node)
	_refresh_environment_lights()
	_light_elapsed = 0.0
	_update_processing()
	if previous_quality != quality:
		quality_changed.emit()

func foreground_frame_cap() -> int:
	var cap := frame_limit
	if cap == 0:
		cap = 30 if quality == 0 else (60 if quality == 1 or OS.has_feature("mobile") else -1)
	return maxi(0, cap)


func lifecycle_frame_cap(foreground: int, mobile: bool, focused: bool, paused: bool) -> int:
	if not mobile or (focused and not paused):
		return foreground
	# Keep networking and physics running; only lower the render/process cap.
	var ceiling := 15 if paused else 30
	return mini(foreground, ceiling) if foreground > 0 else ceiling


func _refresh_frame_cap() -> void:
	Engine.max_fps = lifecycle_frame_cap(foreground_frame_cap(), OS.has_feature("mobile"), _app_focused, _app_paused)


func combat_particle_amount(authored: int) -> int:
	# Secondary accents only; never remove the actual hit or cast cue.
	var multiplier := 0.4 if quality == 0 else (0.7 if quality == 1 else 1.0)
	return maxi(1, ceili(authored * multiplier))


func prepare_combat_particles(particles: CPUParticles2D) -> void:
	if not particles.has_meta("combat_authored_amount"):
		particles.set_meta("combat_authored_amount", particles.amount)
	particles.amount = combat_particle_amount(int(particles.get_meta("combat_authored_amount")))


func ambient_multiplier() -> float:
	return 0.0 if quality == 0 else (0.5 if quality == 1 else 1.0)


func minimap_preview_limit(touch: bool) -> float:
	if quality == 0:
		return 512.0
	if quality == 1:
		return 768.0
	return 1024.0 if touch else 1536.0


func minimap_refresh_interval() -> float:
	return 0.2 if quality == 0 else (0.15 if quality == 1 else 0.1)


func atmosphere_refresh_interval() -> float:
	return 0.75 if quality == 0 else (0.5 if quality == 1 else 0.25)


func _update_processing() -> void:
	set_process(quality == 1 or (_app_active and (adaptive_enabled or monitor_enabled)))


func _notification(what: int) -> void:
	match what:
		NOTIFICATION_APPLICATION_FOCUS_OUT: _app_focused = false
		NOTIFICATION_APPLICATION_FOCUS_IN: _app_focused = true
		NOTIFICATION_APPLICATION_PAUSED: _app_paused = true
		NOTIFICATION_APPLICATION_RESUMED: _app_paused = false
		_: return
	var was_active := _app_active
	_app_active = _app_focused and not _app_paused
	_low_samples = 0
	if _app_active and not was_active:
		_warmup = ADAPT_WARMUP
	if _ready_for_lifecycle:
		_refresh_frame_cap()
		_update_processing()


func _process(delta: float) -> void:
	if quality == 1:
		_light_elapsed += delta
		if _light_elapsed >= LIGHT_CULL_INTERVAL:
			_light_elapsed = 0.0
			_refresh_environment_lights()
	if not _app_active or (not adaptive_enabled and not monitor_enabled):
		return
	_sample_elapsed += delta
	if _sample_elapsed < 1.0:
		return
	_sample_elapsed = 0.0
	var fps := float(Engine.get_frames_per_second())
	if monitor_enabled:
		_refresh_monitor(fps)
	if adaptive_enabled and DisplayServer.get_name() != "headless":
		var scene := get_tree().current_scene
		var scene_id := scene.get_instance_id() if is_instance_valid(scene) else 0
		if scene_id != _sample_scene_id:
			_sample_scene_id = scene_id
			_warmup = ADAPT_WARMUP
			_low_samples = 0
		_sample_performance(fps, _can_adapt(scene))


func _can_adapt(scene: Node) -> bool:
	if not _app_active or get_tree().paused or not is_instance_valid(scene):
		return false
	if not (str(scene.name).begins_with("StandaloneZone") or scene.name == &"StandaloneVillage"):
		return false
	for flag in ["portal_load_pending", "fast_travel_pending", "fast_travel_visual_pending", "gerald_backstory_active", "cassien_ritual_active", "ravienna_ending_active"]:
		if bool(scene.get_meta(flag, false)):
			return false
	var player := scene.get("checkpoint_player") as CharacterBody2D
	return is_instance_valid(player) and bool(player.get("input_enabled"))


func _sample_performance(fps: float, eligible: bool) -> void:
	if not adaptive_enabled or quality == 0 or not eligible:
		_low_samples = 0
		return
	if _warmup > 0:
		_warmup -= 1
		return
	# Honor the user's cap. An unlimited cap is evaluated against 60 FPS.
	var target := minf(float(Engine.max_fps), 60.0) if Engine.max_fps > 0 else 60.0
	_low_samples = _low_samples + 1 if fps < target * 0.75 else 0
	if _low_samples >= LOW_FPS_SAMPLES:
		_low_samples = 0
		_warmup = ADAPT_WARMUP
		_apply_quality(quality - 1)


func _update_monitor() -> void:
	if monitor_enabled and not is_instance_valid(_monitor):
		_monitor = MONITOR_SCENE.instantiate() as CanvasLayer
		add_child(_monitor)
	elif not monitor_enabled and is_instance_valid(_monitor):
		_monitor.hide()
		_monitor.queue_free()
		_monitor = null
	if monitor_enabled:
		_refresh_monitor(float(Engine.get_frames_per_second()))


func _refresh_monitor(fps: float) -> void:
	if not is_instance_valid(_monitor):
		return
	var readout := _monitor.get_node("Panel/Readout") as Label
	var memory := Performance.get_monitor(Performance.MEMORY_STATIC) / 1048576.0
	var textures := Performance.get_monitor(Performance.RENDER_TEXTURE_MEM_USED) / 1048576.0
	readout.text = "%d FPS | %s\nEngine RAM %.0f MiB | Textures %.0f MiB" % [int(fps), QUALITY_NAMES[quality], memory, textures]


func _refresh_environment_lights() -> void:
	for node in get_tree().get_nodes_in_group(LIGHT_GROUP):
		_apply_environment_light(node)


func light_intersects_viewport(light: PointLight2D) -> bool:
	if light.texture == null:
		return false
	var extent := light.texture.get_size() * absf(light.texture_scale)
	var bounds := Rect2(light.offset - extent * 0.5, extent)
	var screen_bounds: Rect2 = light.get_global_transform_with_canvas() * bounds
	return light.get_viewport_rect().grow(LIGHT_CULL_MARGIN).intersects(screen_bounds)


func _apply_environment_light(node: Node) -> void:
	if not is_instance_valid(node) or not node.is_inside_tree() or not node is PointLight2D:
		return
	var light := node as PointLight2D
	if not light.has_meta("graphics_original_visible"):
		light.set_meta("graphics_original_visible", light.visible)
	var authored_visible: bool = bool(light.get_meta("graphics_original_visible"))
	var target := authored_visible and (quality == 2 or (quality == 1 and light_intersects_viewport(light)))
	if light.visible != target:
		light.visible = target


func _on_node_added(node: Node) -> void:
	if node.is_in_group(AMBIENT_GROUP):
		_apply_ambient.call_deferred(node)
	if node.is_in_group(LIGHT_GROUP):
		_apply_environment_light.call_deferred(node)

func _apply_ambient(node: Node) -> void:
	if not is_instance_valid(node) or not node.is_inside_tree():
		return
	if node is CPUParticles2D or node is GPUParticles2D:
		if not node.has_meta("graphics_original_amount"):
			node.set_meta("graphics_original_amount", node.amount)
			node.set_meta("graphics_original_emitting", node.emitting)
		var original: int = int(node.get_meta("graphics_original_amount"))
		node.emitting = false
		node.amount = maxi(1, ceili(original * 0.5)) if quality == 1 else original
		node.emitting = quality != 0 and bool(node.get_meta("graphics_original_emitting"))
