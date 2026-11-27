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
var cinematic_count := 0
var _quality_at_start := 2


const OPENING_PATH := "res://assets/cinematics/summoning/summoning_opening_fade.ogv"
const HIGHEST_PATH := "res://assets/cinematics/summoning/summoning_highest_gold_crimson.ogv"

@onready var cinematic_player: VideoStreamPlayer = $CinematicPlayer


func _ready() -> void:
	$CloseSummonButton.text = "SKIP ALL"
	$CloseSummonButton.pressed.connect(skip_all)
	$CardStage/NextButton.pressed.connect(_advance)
	get_viewport().size_changed.connect(_fit_reveal_controls)
	_fit_reveal_controls()

func _fit_reveal_controls() -> void:
	var v := get_viewport_rect().size
	var compact := v.x < 600.0 or v.y < 500.0
	var skip := $CloseSummonButton as Button
	skip.anchor_left = 1.0
	skip.anchor_right = 1.0
	skip.anchor_top = 0
	skip.anchor_bottom = 0
	skip.offset_left = -112
	skip.offset_right = -12
	skip.offset_top = 10
	skip.offset_bottom = 58
	var next := $CardStage/NextButton as Button
	next.anchor_left = 0.5
	next.anchor_right = 0.5
	next.anchor_top = 1.0
	next.anchor_bottom = 1.0
	next.offset_left = -100
	next.offset_right = 100
	next.offset_top = -58
	next.offset_bottom = -10
	next.custom_minimum_size = Vector2(200,48)
	var intro := $CardStage/Intro as Label
	intro.anchor_left = 0.04
	intro.anchor_right = 0.96
	intro.add_theme_font_size_override("font_size",16 if compact else 28)
	intro.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	$CardStage/CharacterName.add_theme_font_size_override("font_size",20 if compact else 30)
	$CardStage/CharacterTitle.add_theme_font_size_override("font_size",12 if compact else 16)
	$CardStage/CharacterArtwork.anchor_bottom = 0.66 if v.y < 500.0 else 0.77
	$CardStage/CharacterName.anchor_top = 0.66 if v.y < 500.0 else 0.76
	$CardStage/CharacterName.anchor_bottom = 0.73 if v.y < 500.0 else 0.82
	$CardStage/CharacterTitle.anchor_top = 0.73 if v.y < 500.0 else 0.82
	$CardStage/CharacterTitle.anchor_bottom = 0.80 if v.y < 500.0 else 0.88

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
	_quality_at_start = GraphicsSettings.quality
	$SigilCenter/SummonSigil.set_process(false)
	cinematic_player.hide()
	if not skipped and _quality_at_start > 0:
		AudioDirector.play_variant("magic_charge", -5.0)
		await _play_stream(OPENING_PATH,12.0)
	var premium_played := false
	for index in results.size():
		if skipped:
			break
		var roll: Dictionary = results[index]
		var rarity := str(roll.get("rarity", "common")).to_lower()
		if rarity in ["legendary", "mythic"] and (_quality_at_start == 2 or (_quality_at_start == 1 and not premium_played)):
			premium_played = true
			await _play_stream(HIGHEST_PATH,8.0)
		if skipped:
			break
		cinematic_player.hide()
		AudioDirector.play_variant("summon_swoosh")
		if rarity in ["legendary", "mythic"]:
			AudioDirector.play_variant(rarity + "_reveal", -2.0)
		await _show_character(roll, index, results.size())
	cinematic_player.stop()
	cinematic_player.stream = null
	cinematic_player.hide()
	reveal_finished.emit()

const UPGRADE := preload("res://scripts/gacha/character_upgrade_card.gd")
const MOB := preload("res://scripts/gacha/mob_summon_reward.gd")

func _show_character(roll: Dictionary, index: int, total: int) -> void:
	var stage := $CardStage
	var rarity := str(roll.get("rarity", "common")).to_lower()
	var character_id := str(roll.get("character_id", ""))
	var definition: CharacterDef = ContentDB.get_character(character_id)
	var art := $CardStage/CharacterArtwork as TextureRect
	var mob := MOB.definition(character_id)
	var upgrade := UPGRADE.definition(character_id)
	art.texture = MOB.texture(mob) if not mob.is_empty() else _character_art(UPGRADE.portrait_id(character_id))
	stage.show()
	$CardStage/Progress.text = "%d / %d" % [index + 1, total]
	$CardStage/Intro.text = rarity.to_upper()
	if bool(roll.get("paid_guaranteed",false)):
		$CardStage/Intro.text += " - PAID MILESTONE: FEATURED"
	$CardStage/Intro.modulate = UITheme.rarity_color(rarity)
	$CardStage/CharacterName.text = str(mob.name) if not mob.is_empty() else (definition.display_name if definition != null else character_id.capitalize())
	$CardStage/CharacterTitle.text = MOB.description(roll.get("items", mob.items)) if not mob.is_empty() else (definition.title if definition != null else "")
	if not upgrade.is_empty():
		$CardStage/CharacterName.text = str(upgrade.name)
		$CardStage/Intro.text = rarity.to_upper() + " UPGRADE CARD"
		$CardStage/CharacterTitle.text = UPGRADE.status(roll)
	if roll.has("mythic_count"):
		var evolved: Array = roll.get("fusions", [])
		$CardStage/CharacterTitle.text += "\n" + ("Fused: " + str(evolved.back().name) if not evolved.is_empty() else "Mythic progress %d/7" % int(roll.mythic_count))
	if roll.has("ascended_count"):
		$CardStage/CharacterTitle.text += "\n" + (CharacterInstance.star_text(int(roll.ascended_count)) + " | +%d%% power" % (4 * clampi(int(roll.ascended_count)-1,0,6)))
	$CardStage/CharacterTitle.modulate = UITheme.rarity_color(rarity)
	$CardStage/NextButton.text = "View all results" if index + 1 == total else "Next reward"
	reveal_count += 1
	var fade: Tween
	if _quality_at_start == 0:
		art.modulate.a = 1.0
		$CardStage/AnimationPlayer.stop()
		$CardStage/Intro.modulate.a = 1.0
	else:
		art.modulate.a = 0.0
		$CardStage/AnimationPlayer.play("mythic" if rarity == "mythic" else ("legendary" if rarity == "legendary" else "standard"))
		fade = create_tween()
		fade.tween_property(art, "modulate:a", 1.0, 0.65 if rarity in ["legendary", "mythic"] else 0.35)
	waiting_for_card = true
	await advance_requested
	waiting_for_card = false
	if fade != null: fade.kill()
	stage.hide()
	art.texture = null

func _character_art(character_id: String) -> Texture2D:
	var approved := preload("res://scripts/art/approved_character_portraits.gd").texture(character_id)
	if approved != null: return approved
	var base := character_id
	for suffix in ["_common", "_rare", "_epic", "_legendary", "_mythic"]:
		base = base.trim_suffix(suffix)
	# Temporary portrait presentation for the original trio until their new
	# full-body summon illustrations are approved.
	if base in ["kael", "gerald", "lilith"]:
		var portrait_path := "res://assets/portraits/summon/%s.png" % base
		if ResourceLoader.exists(portrait_path):
			return load(portrait_path) as Texture2D
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


func _play_stream(path: String, timeout_seconds: float) -> void:
	if skipped or not is_instance_valid(cinematic_player) or not ResourceLoader.exists(path):
		return
	var stream := load(path) as VideoStream
	if stream == null: return
	cinematic_player.stop()
	cinematic_player.stream = stream
	cinematic_player.show()
	cinematic_count += 1
	# Arm both completion paths before play(). This avoids losing a very early
	# finished signal on fast decoders or tiny/failed media imports.
	var finished_callback := Callable(self, "_on_stream_finished")
	cinematic_player.finished.connect(finished_callback, CONNECT_ONE_SHOT)
	# A failed decoder/import must not trap the player in a permanent summon
	# lock. Normal completion wins; the timer is a safety net for broken media.
	# VideoStreamTheora does not expose get_length() in Godot 4.7.
	# These watchdogs are based on the authored source-video durations
	# (opening 8.064s; rarity clips approximately 5.05s) plus decoder margin.
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
		cinematic_player.stream = null
		cinematic_player.hide()


func _on_stream_finished() -> void:
	stream_completed.emit()


func _on_stream_timeout() -> void:
	stream_completed.emit()
