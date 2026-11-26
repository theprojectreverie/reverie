extends Node

## Standalone integration smoke test for the installed SFX library.
## Run: Godot --headless --path . res://tests/audio_integration_smoke.tscn

var passed := 0
var failed := 0


func check(condition: bool, label: String) -> void:
	if condition:
		passed += 1
	else:
		failed += 1
		push_error("[AudioIntegrationSmoke] " + label)


func _has_playing_stream(stream: AudioStream) -> bool:
	for player in AudioDirector._sfx_players:
		if player.playing and player.stream == stream:
			return true
	return false


func _check_sfx_plays(sound_id: String) -> void:
	AudioDirector.play_sfx(sound_id)
	await get_tree().process_frame
	check(_has_playing_stream(AudioDirector.SFX_STREAMS[sound_id]), "One-shot plays: " + sound_id)


func _ready() -> void:
	check(AudioServer.get_bus_index("SFX") >= 0, "SFX bus exists")
	check(AudioDirector._sfx_players.size() == AudioDirector.SFX_POOL_SIZE, "SFX player pool is created")

	var paths: Array[String] = [
		"res://assets/audio/sfx/ui_crystal_click.mp3",
		"res://assets/audio/sfx/ui_crystal_hover.mp3",
		"res://assets/audio/sfx/ui_confirm_select.mp3",
		"res://assets/audio/sfx/ui_panel_open.mp3",
		"res://assets/audio/sfx/ui_panel_close.mp3",
		"res://assets/audio/sfx/inventory_equip.mp3",
		"res://assets/audio/sfx/summon_ritual_ambience.mp3",
		"res://assets/audio/sfx/summon_reveal.mp3",
		"res://assets/audio/sfx/spell_cast.mp3",
		"res://assets/audio/sfx/frozen_hall_wind_loop.mp3",
	]
	for path in paths:
		var stream := load(path) as AudioStream
		check(stream != null, "Imported stream loads: " + path)
		check(ResourceLoader.exists(path), "Resource path resolves: " + path)

	var default_button := Button.new()
	add_child(default_button)
	default_button.pressed.emit()
	await get_tree().process_frame
	check(_has_playing_stream(AudioDirector.SFX_STREAMS["ui_crystal_click"]), "Default button press plays click")

	var hover_button := Button.new()
	add_child(hover_button)
	hover_button.mouse_entered.emit()
	await get_tree().process_frame
	check(_has_playing_stream(AudioDirector.SFX_STREAMS["ui_crystal_hover"]), "Auto-bound button hover plays hover cue")

	var confirm_button := Button.new()
	add_child(confirm_button)
	AudioDirector.set_button_feedback(confirm_button, "confirm")
	confirm_button.pressed.emit()
	await get_tree().process_frame
	check(_has_playing_stream(AudioDirector.SFX_STREAMS["ui_confirm_select"]), "Confirm-tagged button plays confirm cue")

	for sound_id in [
		"ui_panel_open",
		"ui_panel_close",
		"inventory_equip",
		"spell_cast",
		"summon_reveal",
	]:
		await _check_sfx_plays(sound_id)

	AudioDirector.play_summon_ritual_ambience()
	await get_tree().create_timer(0.65).timeout
	check(_ambience_matches("summon_ritual_ambience"), "Summon ambience starts")
	var summon_stream := AudioDirector._ambience_player.stream as AudioStreamMP3
	check(summon_stream != null and summon_stream.loop, "Summon ambience is configured to loop")
	check(is_equal_approx(AudioDirector._ambience_player.volume_db, -10.0), "Summon ambience fades to its configured playback gain")

	AudioDirector.stop_summon_ritual_ambience()
	await get_tree().create_timer(0.55).timeout
	check(AudioDirector._ambience_id == "" and not AudioDirector._ambience_player.playing, "Summon ambience fades out cleanly")

	AudioDirector.sync_region_ambience("gothic_castle_boss_zone")
	await get_tree().create_timer(0.85).timeout
	check(_ambience_matches("frozen_hall_wind_loop"), "Gothic Castle starts frozen-hall wind")
	var wind_stream := AudioDirector._ambience_player.stream as AudioStreamMP3
	check(wind_stream != null and wind_stream.loop, "Frozen-hall wind is configured to loop")
	check(is_equal_approx(AudioDirector._ambience_player.volume_db, -8.0), "Frozen-hall wind fades to its configured playback gain")

	AudioDirector.sync_region_ambience("greenward")
	await get_tree().create_timer(0.65).timeout
	check(AudioDirector._ambience_id == "" and not AudioDirector._ambience_player.playing, "Leaving Gothic Castle fades wind out")

	AudioDirector.stop_all_audio_immediately()
	await get_tree().create_timer(0.35).timeout
	print("AUDIO INTEGRATION SMOKE: %d passed, %d failed" % [passed, failed])
	get_tree().quit(0 if failed == 0 else 1)


func _ambience_matches(sound_id: String) -> bool:
	return AudioDirector._ambience_id == sound_id and AudioDirector._ambience_player.playing
