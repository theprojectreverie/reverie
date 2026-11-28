extends Node

class TestAvatar:
	extends CharacterBody2D
	var avatar_id := "kael"
	var input_enabled := true
	var network_recovery_paused := false

var passed := 0
var failed := 0

func check(ok: bool, label: String) -> void:
	if ok:
		passed += 1
	else:
		failed += 1
		push_error(label)

func _ready() -> void:
	check(AudioDirector.KAEL_VOICES.size() == 15, "Kael count")
	check(AudioDirector.is_kael_voice_id("kael_mythic"), "Playable variant")
	check(not AudioDirector.is_kael_voice_id("kael_boss"), "Boss excluded")
	check(not AudioDirector.is_kael_voice_id("lilith"), "Other character excluded")
	for line in AudioDirector.KAEL_VOICES:
		var stream := load(AudioDirector.KAEL_VOICES[line]) as AudioStream
		check(stream != null and stream.get_length() > 0.0, "Valid clip " + line)
		check(AudioDirector.play_kael_voice(line, self, true), "Play " + line)
		check(AudioDirector._voice_player.stream == stream, "Correct stream " + line)
	check(not AudioDirector.play_gerald_voice("battle/hurt", self), "Cross-character overlap blocked")
	check(not AudioDirector.play_kael_voice("unknown", self, true), "Unknown cue rejected")
	check(AudioDirector.play_sibling_voice_sequence([["kael", "battle/hurt"], ["lilith", "battle/victory"]], self), "Mixed voice queue starts")
	check(AudioDirector._voice_character == "kael", "Kael first")
	await get_tree().create_timer(1.03).timeout
	check(AudioDirector._voice_character == "lilith", "Lilith follows")
	await get_tree().create_timer(1.0).timeout
	check(AudioDirector._voice_player.stream == null, "Queue cleans up")
	var body := TestAvatar.new()
	add_child(body)
	AudioDirector._voice_next_ms = 0
	AudioDirector._kael_walk_remaining = 1.0
	AudioDirector.tick_lilith_exploration(body, 2.0, false)
	check(AudioDirector._kael_walk_remaining == 1.0, "Idle timer unchanged")
	AudioDirector.tick_lilith_exploration(body, 2.0, true)
	check(AudioDirector._voice_character == "kael", "Kael exploration plays")
	var first: String = AudioDirector._kael_last_walk
	check(first != "exploration/memory" and first != "exploration/companion", "Context-specific lines excluded")
	AudioDirector.stop_lilith_voice(body)
	AudioDirector._voice_next_ms = 0
	AudioDirector._kael_walk_remaining = 1.0
	AudioDirector.tick_lilith_exploration(body, 2.0, true)
	check(AudioDirector._kael_last_walk != first, "No immediate repeat")
	body.input_enabled = false
	AudioDirector.tick_lilith_exploration(body, 2.0, true)
	check(AudioDirector._voice_player.stream == null, "Disabled movement stops voice")
	AudioDirector.play_kael_voice("ultimate", body, true)
	body.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame
	check(AudioDirector._voice_player.stream == null, "Freed owner clears voice")
	AudioDirector.stop_all_audio_immediately()
	print("KAEL_VOICE_SMOKE passed=", passed, " failed=", failed)
	await get_tree().create_timer(0.35).timeout
	get_tree().quit(0 if failed == 0 else 1)
