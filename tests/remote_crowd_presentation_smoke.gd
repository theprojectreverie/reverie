extends Node
func _ready() -> void:
	call_deferred("_run")

func _run() -> void:
	var quality := GraphicsSettings.requested_quality
	var fps := GraphicsSettings.frame_limit
	var adaptive := GraphicsSettings.adaptive_enabled
	var monitor := GraphicsSettings.monitor_enabled
	GraphicsSettings.apply_preferences(0, 30, false, false)
	var sync := CoopWorldSyncComponent.new()
	add_child(sync)
	var layer := Node2D.new()
	add_child(layer)
	sync.remote_root = layer
	sync.entities = layer
	for i in range(100):
		var point := Vector2(80 + (i % 10) * 28, 80 + floori(float(i) / 10.0) * 22)
		var peer := sync._ensure_remote("crowd-%d" % i, "Adventurer %d" % i, point, "Dawn Wanderer")
		assert(peer != null)
	assert(sync.remote_players.size() == 100)
	for peer in sync.remote_players.values():
		peer._refresh_presentation_budget()
		assert(peer.visible)
		assert(is_equal_approx(peer.visual.animation_runtime_component.presentation_interval, 1.0 / 15.0))
	var phases: Dictionary = {}
	for peer in sync.remote_players.values():
		phases[peer._presentation_phase] = true
	assert(phases.size() >= 80, "Crowd visibility checks must not share a single phase")
	var first: RemotePlayerAvatar = sync.remote_players["crowd-0"]
	var old_visual := first.visual
	assert(sync._ensure_remote("crowd-0", "Adventurer 0", Vector2.ZERO, "Dawn Wanderer") == first)
	assert(first.visual == old_visual and first.title_label.text == "Dawn Wanderer")
	sync._ensure_remote("crowd-0", "Adventurer 0", Vector2.ZERO, "Arena Sovereign")
	assert(first.title_label.text == "Arena Sovereign")
	first.set_authoritative_position(Vector2(190,190))
	for i in range(60):
		first._process(0.05)
	assert(first.position.distance_to(Vector2(190,190)) < 1.0)
	GraphicsSettings.apply_preferences(1, 60, false, false)
	for peer in sync.remote_players.values():
		assert(peer.visible)
		assert(is_equal_approx(peer.visual.animation_runtime_component.presentation_interval, 1.0 / 30.0))
	GraphicsSettings.apply_preferences(2, 60, false, false)
	for peer in sync.remote_players.values():
		assert(peer.visible and peer.visual.animation_runtime_component.presentation_interval == 0.0)
	GraphicsSettings.apply_preferences(0, 30, false, false)
	for i in range(1,100):
		sync._remove_remote("crowd-%d" % i)
	await get_tree().process_frame
	first._refresh_presentation_budget()
	assert(first.visual.animation_runtime_component.presentation_interval == 0.0)
	assert(first.visible and sync.remote_players.size() == 1)
	sync._clear_remote_players()
	await get_tree().process_frame
	assert(sync.remote_players.is_empty())
	GraphicsSettings.apply_preferences(quality, fps, adaptive, monitor)
	sync.queue_free()
	await get_tree().process_frame
	AudioDirector.stop_all_audio_immediately()
	await get_tree().create_timer(0.5).timeout
	print("REMOTE_CROWD_PRESENTATION_SMOKE_PASS peers=100 low=15Hz medium=30Hz high=full")
	get_tree().quit(0)
