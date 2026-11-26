extends SceneTree

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var audio = root.get_node("AudioDirector")
	var failures := 0
	audio.play_track("exploration", 0.05)
	await create_timer(0.15).timeout
	for track in ["summoning", "combat"]:
		var previous: String = audio.begin_screen_music(track)
		await create_timer(1.0).timeout
		var stream = audio._player.stream
		if previous != "exploration" or audio._current_track_id != track or not audio._player.playing or not stream is AudioStreamMP3 or not stream.loop:
			failures += 1
			push_error("Failed playback: " + track)
		else:
			print("PASS playback and loop: " + track)
		audio.end_screen_music(track, previous)
		await create_timer(1.0).timeout
		if audio._current_track_id != "exploration" or not audio._player.playing:
			failures += 1
			push_error("Failed restoration: " + track)
		else:
			print("PASS restore exploration: " + track)
	for scene_path in ["res://scenes/ui/gacha_screen.tscn", "res://scenes/ui/combat_screen.tscn"]:
		var screen = load(scene_path).instantiate()
		var expected := "summoning" if scene_path.contains("gacha") else "combat"
		if expected == "combat":
			screen.group_id = "elder_hollow"
		root.add_child(screen)
		await create_timer(1.0).timeout
		if audio._current_track_id != expected or not audio._player.playing:
			failures += 1
			push_error("Screen playback failed: " + expected)
		else:
			print("PASS real screen playback: " + expected)
		screen.queue_free()
		await create_timer(1.0).timeout
		if audio._current_track_id != "exploration":
			failures += 1
			push_error("Screen exit restoration failed: " + expected)
		else:
			print("PASS real screen exit: " + expected)
	var previous_fast: String = audio.begin_screen_music("summoning")
	audio.end_screen_music("summoning", previous_fast)
	await create_timer(1.0).timeout
	if audio._current_track_id != "exploration" or not audio._player.playing or not is_equal_approx(audio._player.volume_db, -5.0):
		failures += 1
		push_error("Rapid open/close failed")
	else:
		print("PASS rapid open/close")
	audio.stop_all_audio_immediately()
	await create_timer(0.35).timeout
	print("MUSIC SCREEN TRANSITIONS: %d failures" % failures)
	quit(failures)
