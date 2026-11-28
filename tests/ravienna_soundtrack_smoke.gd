extends Node

func _ready() -> void:
	call_deferred("_run")

func _run() -> void:
	AudioDirector.stop_music_immediately()
	var player := AudioDirector.get_node("MusicPlayer") as AudioStreamPlayer
	assert(AudioDirector.play_track("exploration", 0.05))
	await get_tree().create_timer(0.15).timeout
	for part in [1, 2]:
		var track := "ravienna_story_%d" % part
		var previous := AudioDirector.requested_music_track()
		assert(AudioDirector.play_track(track, 0.05))
		var story := (load("res://scenes/world/six_zone_reverie/crimson_oath_part_%d.tscn" % part) as PackedScene).instantiate() as GeraldBossIntro
		story.music_track_id = track
		story.tree_exiting.connect(AudioDirector.end_screen_music.bind(track, previous), CONNECT_ONE_SHOT)
		add_child(story)
		await get_tree().create_timer(0.35).timeout
		assert(player.playing and AudioDirector.requested_music_track() == track)
		var stream := player.stream
		assert(not stream.get("loop"))
		var playback := story.playback_component
		assert(playback.auto_play and playback.active)
		assert(playback.shots.size() == (14 if part == 1 else 20))
		assert(absf(stream.get_length() - playback._total_duration) < 3.0)
		print("PART ", part, " PASS: ", stream.get_length(), "s, ", playback._total_duration, "s cues, no loop")
		story.input_component.skip_requested.emit()
		await story.finished
		story.queue_free()
		await get_tree().create_timer(1.1).timeout
		assert(AudioDirector.requested_music_track() == "exploration" and player.playing)
		print("PART ", part, " skip/restoration PASS")
	var previous := AudioDirector.begin_screen_music("ravienna_boss")
	await get_tree().create_timer(1.0).timeout
	assert(player.playing and player.stream.get("loop"))
	assert(player.stream.resource_path.ends_with("wrath_of_the_fallen.mp3"))
	AudioDirector.end_screen_music("ravienna_boss", previous)
	await get_tree().create_timer(1.0).timeout
	assert(AudioDirector.requested_music_track() == "exploration" and player.playing)
	print("BOSS loop/restoration PASS")
	await AudioDirector.drain_for_shutdown()
	get_tree().quit()
