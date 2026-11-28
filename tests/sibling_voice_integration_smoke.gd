extends Node

class TestAvatar:
	extends CharacterBody2D
	var avatar_id := "gerald"
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
	check(AudioDirector.GERALD_VOICES.size() == 15, "Gerald count")
	check(AudioDirector.LILITH_VOICES.size() == 16, "Lilith count")
	for line in AudioDirector.GERALD_VOICES:
		var stream := load(AudioDirector.GERALD_VOICES[line]) as AudioStream
		check(stream != null and stream.get_length() > 0.0, "Gerald clip " + line)
		check(AudioDirector.play_gerald_voice(line, self, true), "Gerald plays " + line)
		check(AudioDirector._voice_player.stream == stream, "Gerald correct stream " + line)
	for line in AudioDirector.LILITH_VOICES:
		var stream: AudioStream = AudioDirector.LILITH_VOICES[line]
		check(stream != null and stream.get_length() > 0.0, "Lilith clip " + line)
		check(AudioDirector.play_lilith_voice(line, self, true), "Lilith plays " + line)
		check(AudioDirector._voice_player.stream == stream, "Lilith correct stream " + line)
	check(not AudioDirector.play_gerald_voice("battle/hurt", self), "Shared overlap guard")
	check(AudioDirector.is_gerald_voice_id("gerald_mythic"), "Gerald variants")
	check(not AudioDirector.is_gerald_voice_id("gerald_boss"), "Enemy Gerald excluded")
	check(AudioDirector.play_sibling_voice_sequence([["gerald", "battle/victory"], ["lilith", "battle/victory"]], self), "Sequence starts")
	check(AudioDirector._voice_character == "gerald" and AudioDirector._voice_queue.size() == 1, "Gerald first")
	await get_tree().create_timer(1.3).timeout
	check(AudioDirector._voice_character == "lilith" and AudioDirector._voice_queue.is_empty(), "Lilith next without overlap")
	await get_tree().create_timer(1.0).timeout
	check(AudioDirector._voice_player.stream == null, "Sequence releases stream")
	var body := TestAvatar.new()
	add_child(body)
	AudioDirector._voice_next_ms = 0
	AudioDirector._gerald_walk_remaining = 1.0
	AudioDirector.tick_lilith_exploration(body, 2.0, false)
	check(AudioDirector._gerald_walk_remaining == 1.0, "Idle does not advance walk timer")
	AudioDirector.tick_lilith_exploration(body, 2.0, true)
	check(AudioDirector._voice_character == "gerald", "Gerald exploration plays")
	var first: String = AudioDirector._gerald_last_walk
	AudioDirector.stop_lilith_voice(body)
	AudioDirector._voice_next_ms = 0
	AudioDirector._gerald_walk_remaining = 1.0
	AudioDirector.tick_lilith_exploration(body, 2.0, true)
	check(AudioDirector._gerald_last_walk != first, "Gerald no repeats")
	body.avatar_id = "lilith"
	AudioDirector._voice_next_ms = 0
	AudioDirector._lilith_walk_remaining = 1.0
	AudioDirector.tick_lilith_exploration(body, 2.0, true)
	check(AudioDirector._voice_character == "lilith", "Switch to Lilith exploration")
	body.input_enabled = false
	AudioDirector.tick_lilith_exploration(body, 2.0, true)
	check(AudioDirector._voice_player.stream == null, "Disabled input stops voice")
	AudioDirector.play_sibling_voice_sequence([["gerald", "protect_lilith"], ["lilith", "battle/entrance"]], body)
	body.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame
	check(AudioDirector._voice_player.stream == null and AudioDirector._voice_queue.is_empty(), "Owner removal clears sequence")
	AudioDirector.stop_all_audio_immediately()
	print("SIBLING_VOICE_SMOKE passed=", passed, " failed=", failed)
	await get_tree().create_timer(0.35).timeout
	get_tree().quit(0 if failed == 0 else 1)
