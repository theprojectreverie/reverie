extends SceneTree

func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var main_scene := load("res://scenes/main.tscn") as PackedScene
	assert(main_scene != null, "Main scene loads")
	var main := main_scene.instantiate()
	root.add_child(main)
	await create_timer(0.5).timeout
	var audio_director := root.get_node("AudioDirector")
	var music_player := audio_director.get_node("MusicPlayer") as AudioStreamPlayer
	assert(music_player != null and music_player.playing, "Title music starts during main-scene startup")
	audio_director.stop_all_audio_immediately()
	assert(not music_player.playing and music_player.stream == null, "Shutdown stops music and releases the stream")
	await create_timer(0.35).timeout
	assert(not music_player.playing and music_player.stream == null, "Audio mixer drain leaves no active stream")
	print("MAIN_AUDIO_SHUTDOWN_PASS title_music=started stream=cleared mixer_drain=350ms")
	quit()
