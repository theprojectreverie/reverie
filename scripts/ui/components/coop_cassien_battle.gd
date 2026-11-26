extends Control
## Cosmetic playback only. HP, damage and rewards remain server-owned.
@onready var art: AnimatedSprite2D = $Center/Panel/Content/Portrait/Cassien
@onready var portrait: Control = $Center/Panel/Content/Portrait
var _hp := 600.0
var _defeated := false
var _pending: Array[StringName] = []

func _ready() -> void:
	art.animation_finished.connect(_next_clip)
	portrait.resized.connect(_center_art)
	_center_art()
	art.play(&"idle")

func _center_art() -> void:
	art.position = Vector2(portrait.size.x * 0.5, portrait.size.y - 10.0)

func apply_state(hp: float, counter: bool, live: bool, special: String = "") -> void:
	var previous := _hp
	_hp = hp
	if hp <= 0.0:
		if _defeated:
			return
		_defeated = true
		_pending.clear()
		art.play(&"defeat")
		if not live:
			art.pause()
			art.frame = art.sprite_frames.get_frame_count(&"defeat") - 1
		return
	if _defeated:
		_defeated = false
		_pending.clear()
		art.play(&"idle")
	if live and not special.is_empty():
		_pending.clear()
		art.play(&"crimson_requiem" if special == "Crimson Requiem" else &"crimson_crescent")
		art.set_frame_and_progress(0, 0.0)
		return
	if not live or hp >= previous:
		return
	# Collapse burst traffic to a short bounded visual queue; never delay server state.
	if _pending.size() < 2:
		_pending.append(&"hit")
	if counter and _pending.size() < 3:
		_pending.append(&"attack")
	if art.animation == &"idle" or not art.is_playing():
		_next_clip()

func _next_clip() -> void:
	if _defeated:
		return
	if _pending.is_empty():
		art.play(&"idle")
		return
	var clip: StringName = _pending.pop_front()
	art.play(clip)
	art.set_frame_and_progress(0, 0.0)
