extends Node
var passed := 0
var failed := 0

func check(value: bool, label: String) -> void:
	if value:
		passed += 1
	else:
		failed += 1
		push_error(label)

func _ready() -> void:
	check(AudioDirector.LILITH_VOICES.size() == 16, "All 16 clips registered")
	for line in AudioDirector.LILITH_VOICES:
		var stream: AudioStream = AudioDirector.LILITH_VOICES[line]
		check(stream != null and stream.get_length() > 0.0, "Valid clip " + line)
		check(AudioDirector.play_lilith_voice(line, self, true), "Play " + line)
		check(AudioDirector._voice_player.stream == stream, "Correct stream " + line)
	check(AudioDirector.is_lilith_voice_id("lilith_mythic"), "Variant recognized")
	check(not AudioDirector.is_lilith_voice_id("gerald"), "Other avatar excluded")
	check(not AudioDirector.play_lilith_voice("unknown", self, true), "Unknown cue rejected")
	check(not AudioDirector.play_lilith_voice("battle/hurt", self), "Overlap blocked")
	var other := Node.new()
	add_child(other)
	AudioDirector.stop_lilith_voice(other)
	check(AudioDirector._voice_player.stream != null, "Unrelated owner cannot stop voice")
	AudioDirector.stop_lilith_voice(self)
	check(AudioDirector._voice_player.stream == null, "Owner cleanup")
	AudioDirector.play_lilith_voice("battle/hurt", other, true)
	other.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame
	check(AudioDirector._voice_player.stream == null, "Freed owner cleanup")
	AudioDirector.stop_all_audio_immediately()
	check(AudioDirector._voice_player.stream == null, "Shutdown cleanup")
	print("LILITH_VOICE_SMOKE passed=", passed, " failed=", failed)
	await get_tree().create_timer(0.35).timeout
	get_tree().quit(0 if failed == 0 else 1)
