extends Node

func _ready() -> void:
	call_deferred("_run")

func _run() -> void:
	var original_quality := GraphicsSettings.requested_quality
	var original_fps := GraphicsSettings.frame_limit
	var original_adaptive := GraphicsSettings.adaptive_enabled
	var original_monitor := GraphicsSettings.monitor_enabled
	GraphicsSettings.apply_preferences(0, 30)
	var sync := CoopWorldSyncComponent.new()
	add_child(sync)
	var layer := Node2D.new()
	add_child(layer)
	sync.remote_root = layer
	sync.entities = layer
	var first := sync._ensure_remote("remote-0", "Wanderer", Vector2(100, 100))
	var old_visual := first.visual
	var runtime := first.visual.animation_runtime_component
	first._refresh_presentation_budget()
	assert(first.visible and runtime.presentation_interval == 0.0)
	assert(sync._ensure_remote("remote-0", "Confirmed name", Vector2.ZERO) == first)
	assert(first.name_label.text == "Confirmed name" and first.visual == old_visual)
	for i in range(1, 25):
		var peer := sync._ensure_remote("remote-%d" % i, "Friend %d" % i, Vector2(20000 + i * 100, 20000))
		peer._refresh_presentation_budget()
		assert(not peer.visible and peer.visual.animation_runtime_component.presentation_interval == 0.25)
	assert(sync.remote_players.size() == 25)
	var distant := sync.remote_players["remote-1"] as RemotePlayerAvatar
	var distant_runtime := distant.visual.animation_runtime_component
	distant_runtime.set_process(false)
	var animation_start := distant.visual.anim_time
	for i in range(3):
		distant_runtime._process(0.05)
	assert(is_equal_approx(distant.visual.anim_time, animation_start))
	for i in range(2):
		distant_runtime._process(0.05)
	assert(is_equal_approx(distant.visual.anim_time, animation_start + 0.25))
	distant_runtime.set_process(true)
	sync._apply_position("remote-1", Vector2(100, 100), 1)
	assert(distant.target_position == Vector2(100, 100) and sync.last_sequence == 1)
	for i in range(100):
		distant._process(0.05)
	assert(distant.visible and distant.position.distance_to(Vector2(100, 100)) < 1.0)
	assert(distant_runtime.presentation_interval == 0.0)
	GraphicsSettings.apply_preferences(1, 60)
	var offscreen := sync.remote_players["remote-2"] as RemotePlayerAvatar
	assert(not offscreen.visible and offscreen.visual.animation_runtime_component.presentation_interval == 0.125)
	GraphicsSettings.apply_preferences(2, 60)
	for peer in sync.remote_players.values():
		assert(peer.visible and peer.visual.animation_runtime_component.presentation_interval == 0.0)
	var retired: WeakRef = weakref(offscreen)
	sync._remove_remote("remote-2")
	await get_tree().process_frame
	assert(retired.get_ref() == null and sync.remote_players.size() == 24)
	var layer_ref: WeakRef = weakref(layer)
	sync._clear_remote_players()
	await get_tree().process_frame
	assert(sync.remote_players.is_empty() and layer_ref.get_ref() == null)
	GraphicsSettings.apply_preferences(original_quality, original_fps, original_adaptive, original_monitor)
	sync.queue_free()
	await get_tree().process_frame
	AudioDirector.stop_all_audio_immediately()
	await get_tree().create_timer(0.5).timeout
	print("REMOTE_AVATAR_PERFORMANCE_SMOKE_PASS peers=25")
	get_tree().quit(0)
