class_name LoadingResourceComponent
extends Node
## Owns asynchronous scene loading and reports completion without owning the screen UI.

signal scene_loaded(scene: PackedScene)
signal load_failed

@export var progress_bar_path: NodePath = ^"../LiveArtworkProgressFill"
@export var minimum_display_seconds := 1.15
var target_scene_path := ""
var _elapsed := 0.0
var _progress := 0.0
var _request_failed := false
var _emitted := false
var _progress_bar: ProgressBar
var _shared_dependencies: Array[Resource] = []

func begin(path: String) -> void:
	target_scene_path = path
	_elapsed = 0.0
	_progress = 0.0
	_request_failed = false
	_emitted = false
	_progress_bar = get_node_or_null(progress_bar_path) as ProgressBar
	_shared_dependencies.clear()
	# Compile the shared gameplay/UI graph on the main thread before a worker
	# loads a cold standalone scene. Hold those dependencies until handoff.
	var dependencies: Array[String] = []
	if target_scene_path == "res://scenes/game.tscn":
		dependencies.append("res://scripts/game/game_screen.gd")
	elif target_scene_path.begins_with("res://scenes/world/six_zone_reverie/") or target_scene_path.begins_with("res://scenes/world/village/"):
		dependencies.assign([
			"res://scripts/game/game_overlay_router_component.gd",
			"res://scripts/world/six_zone_reverie/standalone_zone_controller.gd",
			"res://scripts/game/game_combat_router_component.gd",
			"res://scripts/world/six_zone_reverie/zone_ui_binding.gd",
			"res://scenes/ui/game_ui.tscn",
		])
	for dependency in dependencies:
		var resource := load(dependency)
		if resource == null:
			_request_failed = true
			set_process(true)
			return
		_shared_dependencies.append(resource)
	var error := ResourceLoader.load_threaded_request(target_scene_path, "PackedScene", false)
	if error != OK and error != ERR_BUSY:
		_request_failed = true
	set_process(true)

func _process(delta: float) -> void:
	if _emitted:
		return
	_elapsed += delta
	var actual_progress: Array = []
	var status := ResourceLoader.load_threaded_get_status(target_scene_path, actual_progress)
	if not actual_progress.is_empty():
		_progress = maxf(_progress, float(actual_progress[0]) * 100.0)
	_progress = maxf(_progress, minf(82.0, _elapsed * 38.0))
	if status == ResourceLoader.THREAD_LOAD_LOADED:
		_progress = 100.0
	if _progress_bar != null:
		_progress_bar.value = _progress
	var display_floor := minf(minimum_display_seconds, 0.35) if GraphicsSettings.quality == 0 else minimum_display_seconds
	if _elapsed < display_floor:
		return
	if status == ResourceLoader.THREAD_LOAD_LOADED:
		var packed := ResourceLoader.load_threaded_get(target_scene_path) as PackedScene
		_emitted = true
		set_process(false)
		if packed != null and packed.can_instantiate():
			scene_loaded.emit(packed)
		else:
			load_failed.emit()
		_shared_dependencies.clear()
	elif status == ResourceLoader.THREAD_LOAD_FAILED or status == ResourceLoader.THREAD_LOAD_INVALID_RESOURCE or _request_failed:
		_emitted = true
		set_process(false)
		load_failed.emit()
		_shared_dependencies.clear()
