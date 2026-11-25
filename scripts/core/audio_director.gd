extends Node
## Central owner for music, one-shot SFX, ambience and UI feedback.
const BUS_LAYOUT: AudioBusLayout = preload("res://resources/audio/reverie_audio_bus_layout.tres")
const TRACKS := {
	"summoning": "res://assets/audio/music/celestial_summoning_2.mp3",
	"combat": "res://assets/audio/music/weight_of_the_burning_plate.mp3",
	"main_theme": "res://assets/audio/music/crown_of_ash_and_rose.mp3",
	"title_screen": "res://assets/audio/music/the_frozen_kingdom.mp3",
	"exploration": "res://assets/audio/music/the_frozen_kingdom.mp3",
	"kael_prologue": "res://assets/audio/music/fading_into_the_void.mp3",
}
const SFX_STREAMS := {
	"training_ground_ambience": preload("res://assets/audio/sfx/ambience/training_ground_ambience.ogg"),
	"willow_fields_ambience": preload("res://assets/audio/sfx/ambience/willow_fields_ambience.ogg"),
	"royal_gardens_ambience": preload("res://assets/audio/sfx/ambience/royal_gardens_ambience.ogg"),
	"royal_gate_ambience": preload("res://assets/audio/sfx/ambience/royal_gate_ambience.ogg"),
	"ui_crystal_click": preload("res://assets/audio/sfx/ui_crystal_click.mp3"),
	"ui_crystal_hover": preload("res://assets/audio/sfx/ui_crystal_hover.mp3"),
	"ui_confirm_select": preload("res://assets/audio/sfx/ui_confirm_select.mp3"),
	"ui_panel_open": preload("res://assets/audio/sfx/ui_panel_open.mp3"),
	"ui_panel_close": preload("res://assets/audio/sfx/ui_panel_close.mp3"),
	"inventory_equip": preload("res://assets/audio/sfx/inventory_equip.mp3"),
	"summon_ritual_ambience": preload("res://assets/audio/sfx/summon_ritual_ambience.mp3"),
	"summon_reveal": preload("res://assets/audio/sfx/summon_reveal.mp3"),
	"spell_cast": preload("res://assets/audio/sfx/spell_cast.mp3"),
	"frozen_hall_wind_loop": preload("res://assets/audio/sfx/frozen_hall_wind_loop.mp3"),
}
const EXTENDED_SFX := {
	"chest_open": 1,
	"critical_hit": 2,
	"crystal_shatter": 2,
	"defeat": 3,
	"dirt_step": 4,
	"female_hurt": 4,
	"grass_step": 4,
	"healing": 2,
	"item_pickup": 2,
	"legendary_reveal": 1,
	"level_up": 1,
	"magic_charge": 1,
	"magic_impact": 3,
	"magic_projectile": 3,
	"male_hurt": 4,
	"monster_growl": 3,
	"mythic_reveal": 1,
	"portal_transition": 1,
	"quest_complete": 1,
	"shield_block": 2,
	"slime_hurt": 4,
	"stone_step": 4,
	"summon_swoosh": 4,
	"sword_impact": 3,
	"sword_swing": 3,
}
var _last_sfx_variant: Dictionary = {}
const SFX_POOL_SIZE := 8

@onready var _player: AudioStreamPlayer = $MusicPlayer
var _current_track_id := ""
var _requested_track_id := ""
var _fade_tween: Tween
var _sfx_players: Array[AudioStreamPlayer] = []
var _sfx_next_player := 0
var _ambience_player: AudioStreamPlayer
var _ambience_tween: Tween
var _ambience_id := ""
var _region_ambience_id := ""
var _ambience_requested := ""


func _ready() -> void:
	# Install the authored bus layout before any screen can adjust volume.
	AudioServer.set_bus_layout(BUS_LAYOUT)
	_player.bus = "Music"
	_create_sfx_players()
	if not get_tree().node_added.is_connected(_on_scene_node_added):
		get_tree().node_added.connect(_on_scene_node_added)
	call_deferred("_bind_existing_buttons")


func _create_sfx_players() -> void:
	_ambience_player = AudioStreamPlayer.new()
	_ambience_player.name = "AmbiencePlayer"
	_ambience_player.bus = "SFX"
	add_child(_ambience_player)
	for index in range(SFX_POOL_SIZE):
		var audio_player := AudioStreamPlayer.new()
		audio_player.name = "SFXPlayer%d" % index
		audio_player.bus = "SFX"
		add_child(audio_player)
		_sfx_players.append(audio_player)


func play_main_theme(fade_duration: float = 1.8) -> bool:
	return play_track("main_theme", fade_duration)


func play_title_theme(fade_duration: float = 1.8) -> bool:
	return play_track("title_screen", fade_duration)


func play_kael_prologue(fade_duration: float = 1.5) -> bool:
	return play_track("kael_prologue", fade_duration)


func play_exploration_theme(fade_duration: float = 2.2) -> bool:
	return play_track("exploration", fade_duration)


## Screen music temporarily replaces the underlying track.
func begin_screen_music(track_id: String) -> String:
	var previous := _requested_track_id
	play_track(track_id, 0.8)
	return previous

func end_screen_music(track_id: String, previous: String) -> void:
	if _requested_track_id != track_id:
		return
	if previous.is_empty():
		stop_music(0.8)
	else:
		play_track(previous, 0.8)

## Switch the central music player to a registered track.
func play_track(track_id: String, fade_duration: float = 1.8) -> bool:
	if not TRACKS.has(track_id):
		push_warning("[AudioDirector] Unknown music track: " + track_id)
		return false
	if _requested_track_id == track_id and (_player.playing or (_fade_tween != null and _fade_tween.is_running())):
		return true
	var path: String = TRACKS[track_id]
	if not ResourceLoader.exists(path):
		push_warning("[AudioDirector] Music file is not installed yet: " + path)
		return false
	if _fade_tween != null and _fade_tween.is_running():
		_fade_tween.kill()
	_requested_track_id = track_id
	var duration := maxf(fade_duration, 0.05)
	if _current_track_id == track_id and _player.playing:
		_fade_tween = create_tween()
		_fade_tween.tween_property(_player, "volume_db", -5.0, duration).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
		return true
	if _player.playing:
		_fade_tween = create_tween()
		_fade_tween.tween_property(_player, "volume_db", -48.0, duration * 0.5).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
		_fade_tween.tween_callback(_start_track.bind(track_id, duration * 0.5))
	else:
		_start_track(track_id, duration)
	return true


func stop_music(fade_duration: float = 1.0) -> void:
	_requested_track_id = ""
	if not _player.playing:
		_current_track_id = ""
		return
	if _fade_tween != null and _fade_tween.is_running():
		_fade_tween.kill()
	_fade_tween = create_tween()
	_fade_tween.tween_property(_player, "volume_db", -48.0, maxf(fade_duration, 0.05))
	_fade_tween.tween_callback(_stop_player)


func _start_track(track_id: String, fade_duration: float) -> void:
	var stream := load(TRACKS[track_id]) as AudioStream
	if stream == null:
		push_warning("[AudioDirector] Could not load music track: " + TRACKS[track_id])
		return
	if stream is AudioStreamMP3:
		(stream as AudioStreamMP3).loop = true
	elif stream is AudioStreamOggVorbis:
		(stream as AudioStreamOggVorbis).loop = true
	_player.stop()
	_player.stream = stream
	_player.volume_db = -48.0
	_player.play()
	_current_track_id = track_id
	_fade_tween = create_tween()
	_fade_tween.tween_property(_player, "volume_db", -5.0, maxf(fade_duration, 0.05)).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)


func _stop_player() -> void:
	_player.stop()
	_current_track_id = ""


## Public one-shot API. A small pool allows overlapping clicks and combat cues.
func play_sfx(sound_id: String, volume_db: float = -4.0) -> void:
	if not SFX_STREAMS.has(sound_id):
		push_warning("[AudioDirector] Unknown SFX: " + sound_id)
		return
	_play_sfx_stream(SFX_STREAMS[sound_id], volume_db)

func play_variant(category: String, volume_db: float = -2.0) -> void:
	var count := int(EXTENDED_SFX.get(category, 0))
	if count <= 0:
		return
	var last := int(_last_sfx_variant.get(category, 0))
	var index := randi_range(1, count)
	if count > 1 and index == last:
		index = index % count + 1
	var path := "res://assets/audio/sfx/extended/%s/%s_%d.wav" % [category, category, index]
	if not ResourceLoader.exists(path):
		return
	var stream := load(path) as AudioStream
	if stream == null:
		return
	_last_sfx_variant[category] = index
	_play_sfx_stream(stream, volume_db)

func play_damage_reaction(unit: Combatant) -> void:
	if unit == null:
		return
	var id := unit.def_id
	if id.contains("slime"):
		play_variant("slime_hurt")
	elif id.begins_with("kael") or id.begins_with("gerald") or id.begins_with("cassien"):
		play_variant("male_hurt")
	elif id.begins_with("ravienna") or id.begins_with("nyx") or id.begins_with("crimson_witch") or id.begins_with("elathra") or id.begins_with("seraphine"):
		play_variant("female_hurt")
	elif unit.team == 1:
		play_variant("monster_growl", -5.0)

func _play_sfx_stream(stream: AudioStream, volume_db: float) -> void:
	if _sfx_players.is_empty():
		return
	var selected: AudioStreamPlayer
	for offset in range(_sfx_players.size()):
		var index := (_sfx_next_player + offset) % _sfx_players.size()
		if not _sfx_players[index].playing:
			selected = _sfx_players[index]
			_sfx_next_player = (index + 1) % _sfx_players.size()
			break
	if selected == null:
		selected = _sfx_players[_sfx_next_player]
		_sfx_next_player = (_sfx_next_player + 1) % _sfx_players.size()
	selected.stop()
	selected.stream = stream
	selected.volume_db = volume_db
	selected.play()


func play_ui_crystal_click() -> void:
	play_sfx("ui_crystal_click", -4.0)


func play_ui_crystal_hover() -> void:
	play_sfx("ui_crystal_hover", -10.0)


func play_ui_confirm_select() -> void:
	play_sfx("ui_confirm_select", -3.0)


func play_ui_panel_open() -> void:
	play_sfx("ui_panel_open", -3.0)


func play_ui_panel_close() -> void:
	play_sfx("ui_panel_close", -4.0)


func play_inventory_equip() -> void:
	# The equip take needs slightly less gain after peak limiting; compensate
	# here so it sits with the other UI one-shots in actual playback.
	play_sfx("inventory_equip", -1.0)


func play_summon_reveal() -> void:
	play_sfx("summon_reveal", -2.0)


func play_spell_cast() -> void:
	play_sfx("spell_cast", -4.0)


## Mark an important button to use the confirm chime instead of the default click.
func set_button_feedback(button: BaseButton, kind: String = "click") -> void:
	if not is_instance_valid(button):
		return
	button.set_meta("reverie_sfx_kind", kind)
	_bind_button_feedback(button)


func _bind_existing_buttons() -> void:
	if is_inside_tree():
		_bind_buttons_recursive(get_tree().root)


func _bind_buttons_recursive(node: Node) -> void:
	if node is BaseButton:
		_bind_button_feedback(node as BaseButton)
	for child in node.get_children():
		_bind_buttons_recursive(child)


func _on_scene_node_added(node: Node) -> void:
	if node is BaseButton:
		_bind_button_feedback(node as BaseButton)


func _bind_button_feedback(button: BaseButton) -> void:
	if not is_instance_valid(button) or bool(button.get_meta("_reverie_audio_bound", false)):
		return
	button.set_meta("_reverie_audio_bound", true)
	button.mouse_entered.connect(_on_button_hovered.bind(button))
	button.pressed.connect(_on_button_pressed.bind(button))


func _on_button_hovered(button: BaseButton) -> void:
	if not is_instance_valid(button) or button.disabled:
		return
	if bool(button.get_meta("reverie_hover_audio", true)):
		play_ui_crystal_hover()


func _on_button_pressed(button: BaseButton) -> void:
	if not is_instance_valid(button) or button.disabled:
		return
	match str(button.get_meta("reverie_sfx_kind", "click")):
		"confirm":
			play_ui_confirm_select()
		"none":
			return
		_:
			play_ui_crystal_click()


## The ambience channel is exclusive: summon ritual temporarily replaces region ambience.
func play_summon_ritual_ambience() -> void:
	_start_ambience("summon_ritual_ambience", -10.0)


func stop_summon_ritual_ambience() -> void:
	if _ambience_requested != "summon_ritual_ambience" or _ambience_player == null:
		return
	if _ambience_tween != null and _ambience_tween.is_running():
		_ambience_tween.kill()
	_ambience_tween = create_tween()
	_ambience_tween.tween_property(_ambience_player, "volume_db", -48.0, 0.25)
	_ambience_tween.tween_callback(func() -> void:
		_ambience_player.stop()
		_ambience_player.stream = null
		_ambience_id = ""
		if is_inside_tree():
			sync_region_ambience(_region_ambience_id)
	)


func play_frozen_hall_wind_loop() -> void:
	_start_ambience("frozen_hall_wind_loop", -8.0)


func sync_region_ambience(region_id: String) -> void:
	_region_ambience_id = region_id
	match region_id:
		"training_ground":
			_start_ambience("training_ground_ambience", -3.0)
		"willow_fields":
			_start_ambience("willow_fields_ambience", -3.0)
		"castle_royal_gardens":
			_start_ambience("royal_gardens_ambience", -3.0)
		"royal_gate":
			_start_ambience("royal_gate_ambience", -3.0)
		"gothic_castle_boss_zone":
			play_frozen_hall_wind_loop()
		_:
			if not _ambience_id.is_empty():
				stop_ambience(0.45)


func _start_ambience(sound_id: String, volume_db: float) -> void:
	if not SFX_STREAMS.has(sound_id) or _ambience_player == null:
		return
	if _ambience_requested == sound_id and _ambience_id == sound_id and _ambience_player.playing:
		return
	_ambience_requested = sound_id
	if _ambience_tween != null and _ambience_tween.is_running():
		_ambience_tween.kill()
	if _ambience_player.playing:
		_ambience_tween = create_tween()
		_ambience_tween.tween_property(_ambience_player, "volume_db", -48.0, 0.22).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
		_ambience_tween.tween_callback(_begin_ambience.bind(sound_id, volume_db))
	else:
		_begin_ambience(sound_id, volume_db)


func _begin_ambience(sound_id: String, volume_db: float) -> void:
	if _ambience_player == null or not SFX_STREAMS.has(sound_id):
		return
	_ambience_player.stop()
	var stream := SFX_STREAMS[sound_id].duplicate() as AudioStream
	if stream is AudioStreamMP3:
		(stream as AudioStreamMP3).loop = true
	elif stream is AudioStreamOggVorbis:
		(stream as AudioStreamOggVorbis).loop = true
	_ambience_player.stream = stream
	_ambience_player.volume_db = -48.0
	_ambience_player.play()
	_ambience_id = sound_id
	_ambience_tween = create_tween()
	_ambience_tween.tween_property(_ambience_player, "volume_db", volume_db, 0.45).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)


func stop_ambience(fade_duration: float = 0.5) -> void:
	_ambience_requested = ""
	if _ambience_player == null or not _ambience_player.playing:
		_ambience_id = ""
		return
	if _ambience_tween != null and _ambience_tween.is_running():
		_ambience_tween.kill()
	_ambience_tween = create_tween()
	_ambience_tween.tween_property(_ambience_player, "volume_db", -48.0, maxf(fade_duration, 0.05))
	_ambience_tween.tween_callback(func() -> void:
		if _ambience_player != null:
			_ambience_player.stop()
			_ambience_player.stream = null
		_ambience_id = ""
	)


## Immediately releases all playback, streams and tweens. Also used by the headless
## regression runner, which quits without invoking autoload _exit_tree callbacks.
func stop_music_immediately() -> void:
	_requested_track_id = ""
	if _fade_tween != null and _fade_tween.is_running():
		_fade_tween.kill()
	if _player != null:
		_player.stop()
		_player.stream = null
	_current_track_id = ""
	_fade_tween = null


func stop_all_audio_immediately() -> void:
	_ambience_requested = ""
	_region_ambience_id = ""
	stop_music_immediately()
	if _ambience_tween != null and _ambience_tween.is_running():
		_ambience_tween.kill()
	_ambience_tween = null
	if _ambience_player != null:
		_ambience_player.stop()
		_ambience_player.stream = null
	_ambience_id = ""
	for audio_player in _sfx_players:
		if is_instance_valid(audio_player):
			audio_player.stop()
			audio_player.stream = null
	if get_tree() != null and get_tree().node_added.is_connected(_on_scene_node_added):
		get_tree().node_added.disconnect(_on_scene_node_added)


func _exit_tree() -> void:
	stop_all_audio_immediately()
