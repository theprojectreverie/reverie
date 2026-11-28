extends Node

class TestAvatar:
	extends CharacterBody2D
	var avatar_id := "cassien"
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
	check(AudioDirector.CASSIEN_VOICES.size() == 15, "Cassien count")
	check(AudioDirector.is_cassien_voice_id("cassien_mythic"), "Playable variant")
	check(AudioDirector.is_cassien_voice_id("cassien_boss"), "Boss variant")
	check(not AudioDirector.is_cassien_voice_id("mirene"), "Other character excluded")
	for line in AudioDirector.CASSIEN_VOICES:
		var stream := load(AudioDirector.CASSIEN_VOICES[line]) as AudioStream
		check(stream != null and stream.get_length() > 0.0, "Valid clip " + line)
		check(AudioDirector.play_cassien_voice(line, self, true), "Play " + line)
		check(AudioDirector._voice_player.stream == stream, "Correct stream " + line)
	check(not AudioDirector.play_gerald_voice("battle/hurt", self), "Cross-character overlap blocked")
	check(not AudioDirector.play_cassien_voice("unknown", self, true), "Unknown cue rejected")
	check(AudioDirector.play_sibling_voice_sequence([["cassien", "battle/basic_attack"], ["lilith", "battle/victory"]], self), "Mixed voice queue starts")
	check(AudioDirector._voice_character == "cassien", "Cassien first")
	await get_tree().create_timer(1.35).timeout
	check(AudioDirector._voice_character == "lilith", "Lilith follows")
	await get_tree().create_timer(1.0).timeout
	check(AudioDirector._voice_player.stream == null, "Queue cleans up")
	var body := TestAvatar.new()
	add_child(body)
	AudioDirector._voice_next_ms = 0
	AudioDirector._cassien_walk_remaining = 1.0
	AudioDirector.tick_lilith_exploration(body, 2.0, false)
	check(AudioDirector._cassien_walk_remaining == 1.0, "Idle timer unchanged")
	AudioDirector.tick_lilith_exploration(body, 2.0, true)
	check(AudioDirector._voice_character == "cassien", "Cassien exploration plays")
	var first: String = AudioDirector._cassien_last_walk
	AudioDirector.stop_lilith_voice(body)
	AudioDirector._voice_next_ms = 0
	AudioDirector._cassien_walk_remaining = 1.0
	AudioDirector.tick_lilith_exploration(body, 2.0, true)
	check(AudioDirector._cassien_last_walk != first, "No immediate repeat")
	body.input_enabled = false
	AudioDirector.tick_lilith_exploration(body, 2.0, true)
	check(AudioDirector._voice_player.stream == null, "Disabled movement stops voice")
	AudioDirector.play_cassien_voice("battle/ultimate", body, true)
	body.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame
	check(AudioDirector._voice_player.stream == null, "Freed owner clears voice")
	AudioDirector.stop_all_audio_immediately()
	print("CASSIEN_VOICE_SMOKE passed=", passed, " failed=", failed)
	await get_tree().create_timer(0.35).timeout
	get_tree().quit(0 if failed == 0 else 1)
