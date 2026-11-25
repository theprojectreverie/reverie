extends SceneTree

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var audio = root.get_node("AudioDirector")
	var failures := 0
	var checked := 0
	for category in audio.EXTENDED_SFX:
		var count: int = audio.EXTENDED_SFX[category]
		for index in range(1, count + 1):
			var path := "res://assets/audio/sfx/extended/%s/%s_%d.wav" % [category, category, index]
			var stream := load(path) as AudioStream
			if stream == null or stream.get_length() < 0.1:
				failures += 1
				push_error("Invalid stream: " + path)
				continue
			audio._play_sfx_stream(stream, -30.0)
			await process_frame
			var playing := false
			for player in audio._sfx_players:
				if player.playing and player.stream == stream:
					playing = true
			if not playing:
				failures += 1
				push_error("Not playing: " + path)
			checked += 1
		if count > 1:
			audio.play_variant(category, -30.0)
			var previous: int = audio._last_sfx_variant.get(category, 0)
			for i in range(8):
				audio.play_variant(category, -30.0)
				var next: int = audio._last_sfx_variant.get(category, 0)
				if previous == next or next < 1 or next > count:
					failures += 1
					push_error("Repeated or invalid variation: " + category)
				previous = next
	for region in ["training_ground", "castle_royal_gardens", "royal_gate", "willow_fields"]:
		audio.sync_region_ambience(region)
		await create_timer(0.85).timeout
		var stream = audio._ambience_player.stream
		if not stream is AudioStreamOggVorbis or not stream.loop or stream.get_length() < 29.0 or not audio._ambience_player.playing:
			failures += 1
			push_error("Invalid ambience: " + region)
		else:
			print("PASS loop: " + region)
		checked += 1
	audio.play_summon_ritual_ambience()
	await create_timer(0.85).timeout
	audio.stop_summon_ritual_ambience()
	await create_timer(0.95).timeout
	if audio._ambience_id != "willow_fields_ambience":
		failures += 1
		push_error("Region ambience not restored after summoning")
	audio.sync_region_ambience("title_screen")
	await create_timer(0.65).timeout
	if audio._ambience_player.playing:
		failures += 1
		push_error("Region ambience leaks into title")
	audio.stop_all_audio_immediately()
	print("EXTENDED AUDIO: %d assets checked, %d failures" % [checked, failures])
	quit(failures)