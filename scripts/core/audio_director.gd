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
	"gerald_childhood": "res://assets/audio/music/before_the_ashes.mp3",
	"gerald_tragedy": "res://assets/audio/music/the_guardian_who_failed.mp3",
	"ravienna_story_1": "res://assets/audio/music/forbidden_blossoms.mp3",
	"ravienna_story_2": "res://assets/audio/music/the_adagio_of_unresolved_grief.ogg",
	"ravienna_boss": "res://assets/audio/music/wrath_of_the_fallen.mp3",
}
const SFX_STREAMS := {
	"ui_crystal_click": preload("res://assets/audio/sfx/ui_crystal_click.mp3"),
	"ui_crystal_hover": preload("res://assets/audio/sfx/ui_crystal_hover.mp3"),
	"ui_confirm_select": preload("res://assets/audio/sfx/ui_confirm_select.mp3"),
	"ui_panel_open": preload("res://assets/audio/sfx/ui_panel_open.mp3"),
	"ui_panel_close": preload("res://assets/audio/sfx/ui_panel_close.mp3"),
	"inventory_equip": preload("res://assets/audio/sfx/inventory_equip.mp3"),
	"summon_reveal": preload("res://assets/audio/sfx/summon_reveal.mp3"),
	"spell_cast": preload("res://assets/audio/sfx/spell_cast.mp3"),
}
const AMBIENCE_PATHS := {
	"training_ground_ambience": "res://assets/audio/sfx/ambience/training_ground_ambience.ogg",
	"willow_fields_ambience": "res://assets/audio/sfx/ambience/willow_fields_ambience.ogg",
	"royal_gardens_ambience": "res://assets/audio/sfx/ambience/royal_gardens_ambience.ogg",
	"royal_gate_ambience": "res://assets/audio/sfx/ambience/royal_gate_ambience.ogg",
	"summon_ritual_ambience": "res://assets/audio/sfx/summon_ritual_ambience.mp3",
	"frozen_hall_wind_loop": "res://assets/audio/sfx/frozen_hall_wind_loop.mp3",
}
const EXTENDED_SFX := {
	"chest_open": 1,
	"critical_hit": 2,
	"crystal_shatter": 2,
	"defeat": 3,
	"dirt_step": 3,
	"wood_step": 4,
	"water_step": 4,
	"water_entry": 3,
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

const LILITH_VOICES := {
	"summon_greeting": preload("res://assets/audio/voice/lilith/summon_greeting.wav"),
	"gerald_tease": preload("res://assets/audio/voice/lilith/gerald_tease.wav"),
	"ghosts_call": preload("res://assets/audio/voice/lilith/ghosts_call.wav"),
	"gerald_distress": preload("res://assets/audio/voice/lilith/gerald_distress.wav"),
	"battle/entrance": preload("res://assets/audio/voice/lilith/battle/entrance.wav"),
	"battle/basic_attack": preload("res://assets/audio/voice/lilith/battle/basic_attack.wav"),
	"battle/special_attack": preload("res://assets/audio/voice/lilith/battle/special_attack.wav"),
	"battle/hurt": preload("res://assets/audio/voice/lilith/battle/hurt.wav"),
	"battle/low_health": preload("res://assets/audio/voice/lilith/battle/low_health.wav"),
	"battle/victory": preload("res://assets/audio/voice/lilith/battle/victory.wav"),
	"exploration/next_destination": preload("res://assets/audio/voice/lilith/exploration/next_destination.wav"),
	"exploration/wait_for_me": preload("res://assets/audio/voice/lilith/exploration/wait_for_me.wav"),
	"exploration/shiny_discovery": preload("res://assets/audio/voice/lilith/exploration/shiny_discovery.wav"),
	"exploration/curiosity": preload("res://assets/audio/voice/lilith/exploration/curiosity.wav"),
	"exploration/quiet_surroundings": preload("res://assets/audio/voice/lilith/exploration/quiet_surroundings.wav"),
	"exploration/remember_gerald": preload("res://assets/audio/voice/lilith/exploration/remember_gerald.wav"),
}
const GERALD_VOICES := {
	"battle/entrance": "res://assets/audio/voice/gerald/battle/entrance.wav",
	"battle/basic_attack": "res://assets/audio/voice/gerald/battle/basic_attack.wav",
	"battle/special_attack": "res://assets/audio/voice/gerald/battle/special_attack.wav",
	"battle/hurt": "res://assets/audio/voice/gerald/battle/hurt.wav",
	"battle/low_health": "res://assets/audio/voice/gerald/battle/low_health.wav",
	"battle/victory": "res://assets/audio/voice/gerald/battle/victory.wav",
	"exploration/stay_close": "res://assets/audio/voice/gerald/exploration/stay_close.wav",
	"exploration/keep_moving": "res://assets/audio/voice/gerald/exploration/keep_moving.wav",
	"exploration/unease": "res://assets/audio/voice/gerald/exploration/unease.wav",
	"exploration/quiet": "res://assets/audio/voice/gerald/exploration/quiet.wav",
	"exploration/watch_step": "res://assets/audio/voice/gerald/exploration/watch_step.wav",
	"exploration/find_way": "res://assets/audio/voice/gerald/exploration/find_way.wav",
	"protect_lilith": "res://assets/audio/voice/gerald/protect_lilith.wav",
	"summon_greeting": "res://assets/audio/voice/gerald/summon_greeting.wav",
	"comfort": "res://assets/audio/voice/gerald/comfort.wav",
}
const MIRENE_VOICES := {
	"battle/entrance": "res://assets/audio/voice/mirene/battle/entrance.wav",
	"battle/basic_attack": "res://assets/audio/voice/mirene/battle/basic_attack.wav",
	"battle/hurt": "res://assets/audio/voice/mirene/battle/hurt.wav",
	"battle/low_health": "res://assets/audio/voice/mirene/battle/low_health.wav",
	"battle/defeat": "res://assets/audio/voice/mirene/battle/defeat.wav",
	"battle/victory": "res://assets/audio/voice/mirene/battle/victory.wav",
	"exploration/bored": "res://assets/audio/voice/mirene/exploration/bored.wav",
	"exploration/trouble": "res://assets/audio/voice/mirene/exploration/trouble.wav",
	"exploration/new_stage": "res://assets/audio/voice/mirene/exploration/new_stage.wav",
	"exploration/curiosity": "res://assets/audio/voice/mirene/exploration/curiosity.wav",
	"exploration/trick": "res://assets/audio/voice/mirene/exploration/trick.wav",
	"exploration/surprises": "res://assets/audio/voice/mirene/exploration/surprises.wav",
	"summon_greeting": "res://assets/audio/voice/mirene/summon_greeting.wav",
	"illusion": "res://assets/audio/voice/mirene/illusion.wav",
	"ultimate": "res://assets/audio/voice/mirene/ultimate.wav",
}
var _mirene_walk_remaining := 0.0
var _mirene_last_walk := ""
const CASSIEN_VOICES := {
	"battle/basic_attack": "res://assets/audio/voice/cassien/battle/basic_attack.wav",
	"battle/special_attack": "res://assets/audio/voice/cassien/battle/special_attack.wav",
	"battle/ultimate": "res://assets/audio/voice/cassien/battle/ultimate.wav",
	"battle/hurt": "res://assets/audio/voice/cassien/battle/hurt.wav",
	"battle/low_health": "res://assets/audio/voice/cassien/battle/low_health.wav",
	"battle/victory": "res://assets/audio/voice/cassien/battle/victory.wav",
	"exploration/wounds": "res://assets/audio/voice/cassien/exploration/wounds.wav",
	"exploration/onward": "res://assets/audio/voice/cassien/exploration/onward.wav",
	"exploration/silence": "res://assets/audio/voice/cassien/exploration/silence.wav",
	"exploration/memory": "res://assets/audio/voice/cassien/exploration/memory.wav",
	"exploration/loyalty": "res://assets/audio/voice/cassien/exploration/loyalty.wav",
	"exploration/duty": "res://assets/audio/voice/cassien/exploration/duty.wav",
	"summon_greeting": "res://assets/audio/voice/cassien/summon_greeting.wav",
	"boss_entrance": "res://assets/audio/voice/cassien/boss_entrance.wav",
	"defeat": "res://assets/audio/voice/cassien/defeat.wav",
}
var _cassien_walk_remaining := 0.0
var _cassien_last_walk := ""
const KAEL_VOICES := {
	"battle/entrance": "res://assets/audio/voice/kael/battle/entrance.wav",
	"battle/basic_attack": "res://assets/audio/voice/kael/battle/basic_attack.wav",
	"battle/special_attack": "res://assets/audio/voice/kael/battle/special_attack.wav",
	"battle/hurt": "res://assets/audio/voice/kael/battle/hurt.wav",
	"battle/low_health": "res://assets/audio/voice/kael/battle/low_health.wav",
	"battle/victory": "res://assets/audio/voice/kael/battle/victory.wav",
	"exploration/ahead": "res://assets/audio/voice/kael/exploration/ahead.wav",
	"exploration/keep_going": "res://assets/audio/voice/kael/exploration/keep_going.wav",
	"exploration/curiosity": "res://assets/audio/voice/kael/exploration/curiosity.wav",
	"exploration/memory": "res://assets/audio/voice/kael/exploration/memory.wav",
	"exploration/companion": "res://assets/audio/voice/kael/exploration/companion.wav",
	"exploration/resolve": "res://assets/audio/voice/kael/exploration/resolve.wav",
	"journey": "res://assets/audio/voice/kael/journey.wav",
	"ultimate": "res://assets/audio/voice/kael/ultimate.wav",
	"defeat": "res://assets/audio/voice/kael/defeat.wav",
}
var _kael_walk_remaining := 0.0
var _kael_last_walk := ""
const RAVIENNA_VOICES := {
	"battle/entrance": "res://assets/audio/voice/ravienna/battle/entrance.wav",
	"battle/basic_attack": "res://assets/audio/voice/ravienna/battle/basic_attack.wav",
	"battle/special_attack": "res://assets/audio/voice/ravienna/battle/special_attack.wav",
	"battle/hurt": "res://assets/audio/voice/ravienna/battle/hurt.wav",
	"battle/low_health": "res://assets/audio/voice/ravienna/battle/low_health.wav",
	"battle/defeat": "res://assets/audio/voice/ravienna/battle/defeat.wav",
	"battle/victory": "res://assets/audio/voice/ravienna/battle/victory.wav",
	"exploration/fleeting": "res://assets/audio/voice/ravienna/exploration/fleeting.wav",
	"exploration/proceed": "res://assets/audio/voice/ravienna/exploration/proceed.wav",
	"exploration/secrets": "res://assets/audio/voice/ravienna/exploration/secrets.wav",
	"exploration/sky": "res://assets/audio/voice/ravienna/exploration/sky.wav",
	"exploration/time": "res://assets/audio/voice/ravienna/exploration/time.wav",
	"exploration/silence": "res://assets/audio/voice/ravienna/exploration/silence.wav",
	"summon_greeting": "res://assets/audio/voice/ravienna/summon_greeting.wav",
	"ultimate": "res://assets/audio/voice/ravienna/ultimate.wav",
	"cassien": "res://assets/audio/voice/ravienna/cassien.wav",
}
const ELATHRA_VOICES := {
	"battle/entrance": "res://assets/audio/voice/elathra/battle/entrance.wav",
	"battle/basic_attack": "res://assets/audio/voice/elathra/battle/basic_attack.wav",
	"battle/special_attack": "res://assets/audio/voice/elathra/battle/special_attack.wav",
	"battle/hurt": "res://assets/audio/voice/elathra/battle/hurt.wav",
	"battle/low_health": "res://assets/audio/voice/elathra/battle/low_health.wav",
	"battle/victory": "res://assets/audio/voice/elathra/battle/victory.wav",
	"exploration/bloom": "res://assets/audio/voice/elathra/exploration/bloom.wav",
	"exploration/still": "res://assets/audio/voice/elathra/exploration/still.wav",
	"exploration/memory": "res://assets/audio/voice/elathra/exploration/memory.wav",
	"exploration/further": "res://assets/audio/voice/elathra/exploration/further.wav",
	"exploration/orchid": "res://assets/audio/voice/elathra/exploration/orchid.wav",
	"exploration/wish": "res://assets/audio/voice/elathra/exploration/wish.wav",
	"summon_greeting": "res://assets/audio/voice/elathra/summon_greeting.wav",
	"ultimate": "res://assets/audio/voice/elathra/ultimate.wav",
	"defeat": "res://assets/audio/voice/elathra/defeat.wav",
}
var _final_voice_walk_remaining := {}
var _final_voice_last_walk := {}
var _voice_character := ""
var _voice_queue: Array = []
var _gerald_walk_remaining := 0.0
var _gerald_last_walk := ""
var _voice_player: AudioStreamPlayer
var _voice_owner: Node
var _voice_next_ms := 0
var _lilith_walk_remaining := 0.0
var _lilith_last_walk := ""


func is_lilith_voice_id(id: String) -> bool:
	return id == "lilith" or id.begins_with("lilith_")


func is_gerald_voice_id(id: String) -> bool:
	return id == "gerald" or (id.begins_with("gerald_") and not id.begins_with("gerald_boss"))


func is_mirene_voice_id(id: String) -> bool:
	return id == "mirene" or id.begins_with("mirene_")


func play_mirene_voice(line: String, owner: Node, priority: bool = false) -> bool:
	return play_character_voice("mirene", line, owner, priority)


func is_cassien_voice_id(id: String) -> bool:
	return id == "cassien" or id.begins_with("cassien_")


func play_cassien_voice(line: String, owner: Node, priority: bool = false) -> bool:
	return play_character_voice("cassien", line, owner, priority)


func is_kael_voice_id(id: String) -> bool:
	return id == "kael" or (id.begins_with("kael_") and id != "kael_boss")


func play_kael_voice(line: String, owner: Node, priority: bool = false) -> bool:
	return play_character_voice("kael", line, owner, priority)


func final_voice_character(id: String) -> String:
	if id == "ravienna" or id.begins_with("ravienna_") or id == "revienna" or id.begins_with("revienna_"):
		return "ravienna"
	if id == "elathra" or id.begins_with("elathra_"):
		return "elathra"
	return ""


func _character_voice_registry(character: String) -> Dictionary:
	match character:
		"gerald": return GERALD_VOICES
		"lilith": return LILITH_VOICES
		"mirene": return MIRENE_VOICES
		"cassien": return CASSIEN_VOICES
		"kael": return KAEL_VOICES
		"ravienna": return RAVIENNA_VOICES
		"elathra": return ELATHRA_VOICES
	return {}


func play_lilith_voice(line: String, owner: Node, priority: bool = false) -> bool:
	return play_character_voice("lilith", line, owner, priority)


func play_gerald_voice(line: String, owner: Node, priority: bool = false) -> bool:
	return play_character_voice("gerald", line, owner, priority)


func play_character_voice(character: String, line: String, owner: Node, priority: bool = false) -> bool:
	if not is_instance_valid(_voice_player) or not is_instance_valid(owner) or not owner.is_inside_tree():
		return false
	var registry: Dictionary = _character_voice_registry(character)
	if not registry.has(line):
		return false
	if not priority and (_voice_player.playing or Time.get_ticks_msec() < _voice_next_ms):
		return false
	_voice_queue.clear()
	return _start_character_voice(character, line, owner)


func _start_character_voice(character: String, line: String, owner: Node) -> bool:
	var registry: Dictionary = _character_voice_registry(character)
	if not is_instance_valid(owner) or not owner.is_inside_tree() or not registry.has(line):
		return false
	var stream: AudioStream = load(str(registry[line])) as AudioStream if character != "lilith" else registry[line]
	if stream == null:
		return false
	_voice_player.stop()
	_voice_owner = owner
	_voice_character = character
	_voice_player.stream = stream
	_voice_player.play()
	_voice_next_ms = Time.get_ticks_msec() + 2500
	return true


func play_sibling_voice_sequence(cues: Array, owner: Node) -> bool:
	if cues.is_empty():
		return false
	var first: Array = cues[0]
	if not play_character_voice(str(first[0]), str(first[1]), owner, true):
		return false
	_voice_queue = cues.slice(1)
	return true


func _on_character_voice_finished() -> void:
	if _voice_player.playing:
		return
	_voice_player.stream = null
	if not _voice_queue.is_empty() and is_instance_valid(_voice_owner) and _voice_owner.is_inside_tree():
		var next: Array = _voice_queue.pop_front()
		_start_character_voice(str(next[0]), str(next[1]), _voice_owner)
	else:
		stop_lilith_voice()


func stop_lilith_voice(owner: Node = null) -> void:
	if owner != null and _voice_owner != owner:
		return
	if is_instance_valid(_voice_player):
		_voice_player.stop()
		_voice_player.stream = null
	_voice_owner = null
	_voice_character = ""
	_voice_queue.clear()


func _process(_delta: float) -> void:
	if _voice_player != null and _voice_player.playing and (not is_instance_valid(_voice_owner) or not _voice_owner.is_inside_tree()):
		stop_lilith_voice()


func tick_lilith_exploration(body: CharacterBody2D, delta: float, walking: bool) -> void:
	var id := str(body.get("avatar_id"))
	var character := "gerald" if is_gerald_voice_id(id) else "lilith" if is_lilith_voice_id(id) else "mirene" if is_mirene_voice_id(id) and id != "mirene_boss" else "cassien" if is_cassien_voice_id(id) and id != "cassien_boss" else "kael" if is_kael_voice_id(id) else final_voice_character(id) if not id.ends_with("_boss") else ""
	if character.is_empty() or not bool(body.get("input_enabled")) or bool(body.get("network_recovery_paused")):
		stop_lilith_voice(body)
		return
	if _voice_owner == body and _voice_character != character:
		stop_lilith_voice(body)
	if not walking:
		return
	if character == "gerald":
		_tick_gerald_exploration(body, delta)
		return
	if character == "mirene":
		_tick_mirene_exploration(body, delta)
		return
	if character == "cassien":
		_tick_cassien_exploration(body, delta)
		return
	if character == "kael":
		_tick_kael_exploration(body, delta)
		return
	if character in ["ravienna", "elathra"]:
		_tick_final_voice_exploration(character, body, delta)
		return
	if _lilith_walk_remaining <= 0.0:
		_lilith_walk_remaining = randf_range(45.0, 90.0)
	_lilith_walk_remaining -= delta
	if _lilith_walk_remaining > 0.0:
		return
	var lines: Array[String] = ["exploration/next_destination", "exploration/curiosity", "exploration/quiet_surroundings", "exploration/remember_gerald", "exploration/wait_for_me"]
	for member in GameState.roster_domain.party_instances():
		if str(member.char_id) == "gerald" or str(member.char_id).begins_with("gerald_"):
			lines.append("gerald_tease")
			break
	lines.erase(_lilith_last_walk)
	var line: String = lines.pick_random()
	if play_lilith_voice(line, body):
		_lilith_last_walk = line
	_lilith_walk_remaining = randf_range(45.0, 90.0)


func _tick_gerald_exploration(body: CharacterBody2D, delta: float) -> void:
	if _gerald_walk_remaining <= 0.0:
		_gerald_walk_remaining = randf_range(45.0, 90.0)
	_gerald_walk_remaining -= delta
	if _gerald_walk_remaining > 0.0:
		return
	var lines: Array[String] = ["exploration/stay_close", "exploration/keep_moving", "exploration/unease", "exploration/quiet", "exploration/find_way"]
	for member in GameState.roster_domain.party_instances():
		if is_lilith_voice_id(str(member.char_id)):
			lines.append("exploration/watch_step")
			break
	lines.erase(_gerald_last_walk)
	var line: String = lines.pick_random()
	if play_gerald_voice(line, body):
		_gerald_last_walk = line
	_gerald_walk_remaining = randf_range(45.0, 90.0)


func _tick_mirene_exploration(body: CharacterBody2D, delta: float) -> void:
	if _mirene_walk_remaining <= 0.0:
		_mirene_walk_remaining = randf_range(45.0, 90.0)
	_mirene_walk_remaining -= delta
	if _mirene_walk_remaining > 0.0:
		return
	var lines: Array[String] = ["exploration/bored", "exploration/trouble", "exploration/new_stage", "exploration/curiosity", "exploration/trick", "exploration/surprises"]
	lines.erase(_mirene_last_walk)
	var line: String = lines.pick_random()
	if play_mirene_voice(line, body):
		_mirene_last_walk = line
	_mirene_walk_remaining = randf_range(45.0, 90.0)


func _tick_cassien_exploration(body: CharacterBody2D, delta: float) -> void:
	if _cassien_walk_remaining <= 0.0:
		_cassien_walk_remaining = randf_range(45.0, 90.0)
	_cassien_walk_remaining -= delta
	if _cassien_walk_remaining > 0.0:
		return
	var lines: Array[String] = ["exploration/wounds", "exploration/onward", "exploration/silence", "exploration/memory", "exploration/duty"]
	for member in GameState.roster_domain.party_instances():
		if str(member.char_id).begins_with("ravienna") or str(member.char_id).begins_with("revienna"):
			lines.append("exploration/loyalty")
			break
	lines.erase(_cassien_last_walk)
	var line: String = lines.pick_random()
	if play_cassien_voice(line, body):
		_cassien_last_walk = line
	_cassien_walk_remaining = randf_range(45.0, 90.0)


func _tick_kael_exploration(body: CharacterBody2D, delta: float) -> void:
	if _kael_walk_remaining <= 0.0:
		_kael_walk_remaining = randf_range(45.0, 90.0)
	_kael_walk_remaining -= delta
	if _kael_walk_remaining > 0.0:
		return
	var lines: Array[String] = ["exploration/ahead", "exploration/keep_going", "exploration/curiosity", "exploration/resolve"]
	if body.has_node("FairyCompanion"):
		lines.append("exploration/companion")
	lines.erase(_kael_last_walk)
	var line: String = lines.pick_random()
	if play_kael_voice(line, body):
		_kael_last_walk = line
	_kael_walk_remaining = randf_range(45.0, 90.0)


func _tick_final_voice_exploration(character: String, body: CharacterBody2D, delta: float) -> void:
	var remaining := float(_final_voice_walk_remaining.get(character, 0.0))
	if remaining <= 0.0:
		remaining = randf_range(45.0, 90.0)
	remaining -= delta
	_final_voice_walk_remaining[character] = remaining
	if remaining > 0.0:
		return
	var lines: Array = ["exploration/fleeting", "exploration/proceed", "exploration/secrets", "exploration/sky", "exploration/time", "exploration/silence"] if character == "ravienna" else ["exploration/bloom", "exploration/still", "exploration/memory", "exploration/further", "exploration/wish"]
	if character == "ravienna":
		for member in GameState.roster_domain.party_instances():
			if is_cassien_voice_id(str(member.char_id)):
				lines.append("cassien")
				break
	lines.erase(str(_final_voice_last_walk.get(character, "")))
	var line: String = lines.pick_random()
	if play_character_voice(character, line, body):
		_final_voice_last_walk[character] = line
	_final_voice_walk_remaining[character] = randf_range(45.0, 90.0)


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
	_voice_player = AudioStreamPlayer.new()
	_voice_player.name = "CharacterVoicePlayer"
	_voice_player.bus = "SFX"
	_voice_player.volume_db = -3.0
	add_child(_voice_player)
	_voice_player.finished.connect(_on_character_voice_finished)
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
		audio_player.finished.connect(_release_finished_sfx.bind(audio_player))


func play_main_theme(fade_duration: float = 1.8) -> bool:
	return play_track("main_theme", fade_duration)


func play_title_theme(fade_duration: float = 1.8) -> bool:
	return play_track("title_screen", fade_duration)


func play_kael_prologue(fade_duration: float = 1.5) -> bool:
	return play_track("kael_prologue", fade_duration)


func play_exploration_theme(fade_duration: float = 2.2) -> bool:
	return play_track("exploration", fade_duration)


## Screen music temporarily replaces the underlying track.
## Source clock for music-synchronized cinematic cue sheets.
## Negative means the requested track is still transitioning in.
func music_position_for(track_id: String) -> float:
	if _current_track_id != track_id or not _player.playing:
		return -1.0
	return maxf(0.0, _player.get_playback_position() + AudioServer.get_time_since_last_mix() - AudioServer.get_output_latency())

func requested_music_track() -> String:
	return _requested_track_id

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
		(stream as AudioStreamMP3).loop = not track_id.begins_with("ravienna_story_")
	elif stream is AudioStreamOggVorbis:
		(stream as AudioStreamOggVorbis).loop = not track_id.begins_with("ravienna_story_")
	_player.stop()
	_player.stream = stream
	_player.volume_db = -48.0
	_player.play()
	_current_track_id = track_id
	_fade_tween = create_tween()
	_fade_tween.tween_property(_player, "volume_db", -5.0, maxf(fade_duration, 0.05)).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)


func _stop_player() -> void:
	_player.stop()
	_player.stream = null
	_current_track_id = ""


## Public one-shot API. A small pool allows overlapping clicks and combat cues.
func play_sfx(sound_id: String, volume_db: float = -4.0) -> void:
	var stream := _resolve_sfx(sound_id)
	if stream == null:
		push_warning("[AudioDirector] Unknown or unavailable SFX: " + sound_id)
		return
	_play_sfx_stream(stream, volume_db)


func _resolve_sfx(sound_id: String) -> AudioStream:
	if SFX_STREAMS.has(sound_id):
		return SFX_STREAMS[sound_id] as AudioStream
	var path := str(AMBIENCE_PATHS.get(sound_id, ""))
	return load(path) as AudioStream if not path.is_empty() else null

func play_variant(category: String, volume_db: float = -2.0, pitch_scale: float = 1.0) -> void:
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
	_play_sfx_stream(stream, volume_db, pitch_scale)

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

func _release_finished_sfx(player: AudioStreamPlayer) -> void:
	if is_instance_valid(player) and not player.playing:
		player.stream = null


func _play_sfx_stream(stream: AudioStream, volume_db: float, pitch_scale: float = 1.0) -> void:
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
	selected.pitch_scale = pitch_scale
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
	if not AMBIENCE_PATHS.has(sound_id) or _ambience_player == null:
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
	if _ambience_player == null or not AMBIENCE_PATHS.has(sound_id):
		return
	var source := _resolve_sfx(sound_id)
	if source == null:
		return
	_ambience_player.stop()
	var stream := source.duplicate() as AudioStream
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
	if _ambience_tween != null and _ambience_tween.is_running():
		_ambience_tween.kill()
	_ambience_tween = null
	if _ambience_player == null or not _ambience_player.playing:
		_ambience_id = ""
		if _ambience_player != null:
			_ambience_player.stream = null
		return
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
	stop_lilith_voice()
	_lilith_walk_remaining = 0.0
	_lilith_last_walk = ""
	_gerald_walk_remaining = 0.0
	_gerald_last_walk = ""
	_mirene_walk_remaining = 0.0
	_mirene_last_walk = ""
	_cassien_walk_remaining = 0.0
	_cassien_last_walk = ""
	_kael_walk_remaining = 0.0
	_kael_last_walk = ""
	_final_voice_walk_remaining.clear()
	_final_voice_last_walk.clear()
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


func drain_for_shutdown() -> void:
	stop_all_audio_immediately()
	if is_inside_tree():
		# AudioServer retires stopped playback references on the mixer callback.
		await get_tree().create_timer(0.35, true, false, true).timeout

func _exit_tree() -> void:
	stop_all_audio_immediately()
