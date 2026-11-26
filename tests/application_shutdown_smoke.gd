extends SceneTree
## Exercise the real close notification after the menu root has been replaced.
func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	if OS.get_environment("REVERIE_E2E_DISABLE_LOCAL_SAVE") != "1":
		quit(2)
		return
	var shutdown := root.get_node("ApplicationShutdown")
	assert(not auto_accept_quit)
	var state := root.get_node("GameState")
	state.flags["tutorial_complete"] = true
	state.flags["village_gerald_defeated"] = true
	var error := change_scene_to_file("res://scenes/main.tscn")
	assert(error == OK)
	await scene_changed
	await process_frame
	var old_main: WeakRef = weakref(current_scene)
	error = change_scene_to_file("res://scenes/world/six_zone_reverie/individual_zones/zone_01_royal_gardens_standalone.tscn")
	assert(error == OK)
	await scene_changed
	await process_frame
	assert(old_main.get_ref() == null)
	var audio := root.get_node("AudioDirector")
	audio.play_track("combat", 0.05)
	await create_timer(0.15).timeout
	assert(audio._player.playing)
	assert(not shutdown.quitting)
	root.propagate_notification(Node.NOTIFICATION_WM_CLOSE_REQUEST)
	assert(shutdown.quitting)
	shutdown.request_quit()
	await create_timer(0.10).timeout
	assert(not audio._player.playing and audio._player.stream == null)
	print("APPLICATION_SHUTDOWN_SMOKE_PASS replaced_menu=true audio_cleared=true")
	# The autoload must exit the process by itself, not this test.
