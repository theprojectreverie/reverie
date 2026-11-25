class_name SummonRevealOverlay
extends Control
## Plays the shared summoning opening followed by the rarity-specific reveal.
## The selected character is still supplied by the existing pull result after this sequence.

signal reveal_finished
signal stream_completed
signal advance_requested
var skipped := false
var waiting_for_card := false
var reveal_count := 0


const OPENING_STREAM = preload("res://assets/cinematics/summoning/summoning_opening_fade.ogv")
const STANDARD_STREAM = preload("res://assets/cinematics/summoning/summoning_standard_silver_blue.ogv")
const RARE_STREAM = preload("res://assets/cinematics/summoning/summoning_rare_violet.ogv")
const HIGHEST_STREAM = preload("res://assets/cinematics/summoning/summoning_highest_gold_crimson.ogv")

@onready var cinematic_player: VideoStreamPlayer = $CinematicPlayer


func _ready() -> void:
	$CloseSummonButton.text = "SKIP ALL"
	$CloseSummonButton.pressed.connect(skip_all)
	$CardStage/NextButton.pressed.connect(_advance)

func skip_all() -> void:
	if skipped:
		return
	skipped = true
	stream_completed.emit()
	advance_requested.emit()

func _advance() -> void:
	if waiting_for_card:
		advance_requested.emit()

func play_reveal(rarity: String) -> void:
	await play_batch([{"rarity": rarity}])

func play_batch(results: Array) -> void:
	$Shade.color = Color(0.015, 0.008, 0.035, 1.0)
	$SigilCenter.hide()
	$Title.hide()
	$Subtitle.hide()
	$CardStage.hide()
	cinematic_player.show()
	if not skipped:
		AudioDirector.play_variant("magic_charge", -5.0)
	await _play_stream(OPENING_STREAM)
	for index in results.size():
		if skipped:
			break
		var roll: Dictionary = results[index]
		var rarity := str(roll.get("rarity", "common")).to_lower()
		if rarity in ["legendary", "mythic"]:
			cinematic_player.show()
			await _play_stream(HIGHEST_STREAM)
		if skipped:
			break
		cinematic_player.hide()
		AudioDirector.play_variant("summon_swoosh")
		if rarity in ["legendary", "mythic"]:
			AudioDirector.play_variant(rarity + "_reveal", -2.0)
		await _show_character(roll, index, results.size())
	cinematic_player.stop()
	reveal_finished.emit()

func _show_character(roll: Dictionary, index: int, total: int) -> void:
	var stage := $CardStage
	var rarity := str(roll.get("rarity", "common")).to_lower()
	var character_id := str(roll.get("character_id", ""))
	var definition: CharacterDef = ContentDB.get_character(character_id)
	var art := $CardStage/CharacterArtwork as TextureRect
	art.texture = _character_art(character_id)
	stage.show()
	$CardStage/Progress.text = "%d / %d" % [index + 1, total]
	$CardStage/Intro.text = rarity.to_upper()
	$CardStage/Intro.modulate = UITheme.rarity_color(rarity)
	$CardStage/CharacterName.text = definition.display_name if definition != null else character_id.capitalize()
	$CardStage/CharacterTitle.text = definition.title if definition != null else ""
	$CardStage/CharacterTitle.modulate = UITheme.rarity_color(rarity)
	$CardStage/NextButton.text = "View all results" if index + 1 == total else "Next character"
	reveal_count += 1
	art.modulate.a = 0.0
	$CardStage/AnimationPlayer.play("mythic" if rarity == "mythic" else ("legendary" if rarity == "legendary" else "standard"))
	var fade := create_tween()
	fade.tween_property(art, "modulate:a", 1.0, 0.65 if rarity in ["legendary", "mythic"] else 0.35)
	waiting_for_card = true
	await advance_requested
	waiting_for_card = false
	fade.kill()
	stage.hide()
	art.texture = null

func _character_art(character_id: String) -> Texture2D:
	var base := character_id
	for suffix in ["_common", "_rare", "_epic", "_legendary", "_mythic"]:
		base = base.trim_suffix(suffix)
	var body_base := "kael_avatar" if base == "kael" else base
	# Prefer dedicated aspect artwork. Preserve original authored images.
	for id in [character_id, body_base]:
		var path := "res://assets/characters/%s/full_body_illustration.png" % id
		if ResourceLoader.exists(path):
			return load(path) as Texture2D
	# Temporary authored portrait until the missing full-body artwork is supplied.
	var portrait := PortraitAssetSource.texture_for(character_id, "collection")
	if portrait == null:
		portrait = PortraitAssetSource.texture_for(base, "collection")
	return portrait


func _play_stream(stream: VideoStream) -> void:
	if skipped or stream == null or not is_instance_valid(cinematic_player):
		return
	cinematic_player.stop()
	cinematic_player.stream = stream
	# Arm both completion paths before play(). This avoids losing a very early
	# finished signal on fast decoders or tiny/failed media imports.
	var finished_callback := Callable(self, "_on_stream_finished")
	cinematic_player.finished.connect(finished_callback, CONNECT_ONE_SHOT)
	# A failed decoder/import must not trap the player in a permanent summon
	# lock. Normal completion wins; the timer is a safety net for broken media.
	# VideoStreamTheora does not expose get_length() in Godot 4.7.
	# These watchdogs are based on the authored source-video durations
	# (opening 8.064s; rarity clips approximately 5.05s) plus decoder margin.
	var timeout_seconds := 12.0 if stream == OPENING_STREAM else 8.0
	var finish_timer := get_tree().create_timer(timeout_seconds)
	var timeout_callback := Callable(self, "_on_stream_timeout")
	finish_timer.timeout.connect(timeout_callback, CONNECT_ONE_SHOT)
	cinematic_player.play()
	if not cinematic_player.is_playing():
		if cinematic_player.finished.is_connected(finished_callback):
			cinematic_player.finished.disconnect(finished_callback)
		if finish_timer.timeout.is_connected(timeout_callback):
			finish_timer.timeout.disconnect(timeout_callback)
		return
	await stream_completed
	# Disconnect the losing side of the race so an old timer cannot finish
	# the next rarity video early.
	if is_instance_valid(cinematic_player) and cinematic_player.finished.is_connected(finished_callback):
		cinematic_player.finished.disconnect(finished_callback)
	if finish_timer.timeout.is_connected(timeout_callback):
		finish_timer.timeout.disconnect(timeout_callback)
	if is_instance_valid(cinematic_player):
		cinematic_player.stop()


func _on_stream_finished() -> void:
	stream_completed.emit()


func _on_stream_timeout() -> void:
	stream_completed.emit()


func _stream_for_rarity(rarity: String):
	match rarity.to_lower():
		"epic":
			return RARE_STREAM
		"legendary", "mythic":
			return HIGHEST_STREAM
		_:
			return STANDARD_STREAM
