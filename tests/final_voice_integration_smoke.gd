extends Node

class TestAvatar:
	extends CharacterBody2D
	var avatar_id := "ravienna"
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
	check(AudioDirector.RAVIENNA_VOICES.size() == 16, "Ravienna count")
	check(AudioDirector.ELATHRA_VOICES.size() == 15, "Elathra count")
	check(AudioDirector.final_voice_character("revienna_boss") == "ravienna", "Legacy boss identifier")
	check(AudioDirector.final_voice_character("ravienna_mythic") == "ravienna", "Ravienna variant")
	check(AudioDirector.final_voice_character("elathra_mythic") == "elathra", "Elathra variant")
	check(AudioDirector.final_voice_character("kael").is_empty(), "Other character excluded")
	for character in ["ravienna", "elathra"]:
		var registry: Dictionary = AudioDirector._character_voice_registry(character)
		for line in registry:
			var stream := load(registry[line]) as AudioStream
			check(stream != null and stream.get_length() > 0.0, "Valid clip " + character + "/" + line)
			check(AudioDirector.play_character_voice(character, line, self, true), "Play " + line)
			check(AudioDirector._voice_player.stream == stream, "Correct stream " + line)
	check(not AudioDirector.play_gerald_voice("battle/hurt", self), "Cross-character overlap blocked")
	check(not AudioDirector.play_character_voice("elathra", "unknown", self, true), "Unknown cue rejected")
	check(AudioDirector.play_sibling_voice_sequence([["ravienna", "battle/basic_attack"], ["elathra", "battle/basic_attack"]], self), "Mixed voice queue starts")
	check(AudioDirector._voice_character == "ravienna", "Ravienna first")
	await get_tree().create_timer(1.08).timeout
	check(AudioDirector._voice_character == "elathra", "Elathra follows")
	await get_tree().create_timer(1.35).timeout
	check(AudioDirector._voice_player.stream == null, "Queue cleans up")
	var body := TestAvatar.new()
	add_child(body)
	for character in ["ravienna", "elathra"]:
		body.avatar_id = character
		AudioDirector._voice_next_ms = 0
		AudioDirector._final_voice_walk_remaining[character] = 1.0
		AudioDirector.tick_lilith_exploration(body, 2.0, false)
		check(AudioDirector._final_voice_walk_remaining[character] == 1.0, "Idle timer unchanged " + character)
		AudioDirector.tick_lilith_exploration(body, 2.0, true)
		check(AudioDirector._voice_character == character, "Exploration plays " + character)
		var first: String = AudioDirector._final_voice_last_walk[character]
		check(first != "exploration/orchid", "Orchid line excluded from random speech")
		AudioDirector.stop_lilith_voice(body)
		AudioDirector._voice_next_ms = 0
		AudioDirector._final_voice_walk_remaining[character] = 1.0
		AudioDirector.tick_lilith_exploration(body, 2.0, true)
		check(AudioDirector._final_voice_last_walk[character] != first, "No immediate repeat")
		AudioDirector.stop_lilith_voice(body)
	AudioDirector.play_character_voice("elathra", "ultimate", body, true)
	body.input_enabled = false
	AudioDirector.tick_lilith_exploration(body, 2.0, true)
	check(AudioDirector._voice_player.stream == null, "Disabled movement stops voice")
	AudioDirector.play_character_voice("ravienna", "ultimate", body, true)
	body.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame
	check(AudioDirector._voice_player.stream == null, "Freed owner clears voice")
	AudioDirector.stop_all_audio_immediately()
	print("FINAL_VOICE_SMOKE passed=", passed, " failed=", failed)
	await get_tree().create_timer(0.35).timeout
	get_tree().quit(0 if failed == 0 else 1)
