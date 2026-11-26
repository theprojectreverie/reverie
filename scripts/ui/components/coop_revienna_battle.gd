extends Control
## Cosmetic, server-confirmed playback only. Never changes HP, damage or rewards.
@onready var portrait: Control = $Center/Panel/Content/Portrait
@onready var rig: Node2D = $Center/Panel/Content/Portrait/Revienna
@onready var art: AnimatedSprite2D = rig.get_node("AnimatedSprite2D")
var _hp := 1800.0
var _defeated := false
var _pending: Array[StringName] = []
var _bolt: Sprite2D
var _bolt_tween: Tween
var _eclipse_deadline := 0
var _eclipse_waiting := false
@onready var cracks: AnimatedSprite2D = portrait.get_node("Cracks")
@onready var corona: AnimatedSprite2D = portrait.get_node("Corona")
@onready var eruption: AnimatedSprite2D = portrait.get_node("Eruption")

func _ready() -> void:
	art.animation_finished.connect(_next_clip)
	for fx in [cracks, corona, eruption]:
		fx.animation_finished.connect(fx.hide)
	art.frame_changed.connect(_on_frame)
	portrait.resized.connect(_center_art)
	resized.connect(_fit_panel, CONNECT_DEFERRED)
	$Center/Panel.resized.connect(_fit_panel, CONNECT_DEFERRED)
	_fit_panel.call_deferred()
	_center_art()
	art.play(&"idle")

func _fit_panel() -> void:
	var center: CenterContainer = $Center
	var panel: PanelContainer = $Center/Panel
	center.pivot_offset = center.size * 0.5
	var factor := 1.0
	if size.y > size.x:
		factor = clampf(minf((size.x - 100.0) / maxf(panel.size.x, 1.0), (size.y - 100.0) / maxf(panel.size.y, 1.0)), 1.0, 3.1)
	center.scale = Vector2.ONE * factor

func _center_art() -> void:
	rig.position = Vector2(portrait.size.x * 0.62, portrait.size.y - 12.0)
	rig.scale = Vector2.ONE * minf(1.35, portrait.size.y / 135.0)
	cracks.position = Vector2(portrait.size.x * 0.35, portrait.size.y - 12.0)
	cracks.scale = Vector2(1.0, 0.58)
	eruption.position = cracks.position
	eruption.scale = Vector2.ONE * 0.70
	corona.position = rig.position + Vector2(0, -135)
	corona.scale = Vector2.ONE * 0.72

func apply_state(hp: float, counter: bool, live: bool, special: String = "", phase: int = 1, warning: Dictionary = {}) -> void:
	var previous := _hp
	_hp = hp
	if hp <= 0.0:
		if _defeated:
			return
		_defeated = true
		_pending.clear()
		_clear_bolt()
		_clear_eclipse()
		_play(&"defeat")
		if not live:
			art.pause()
			art.frame = art.sprite_frames.get_frame_count(&"defeat") - 1
		return
	if _defeated:
		_defeated = false
		_pending.clear()
		_play(&"idle")
	if str(warning.get("name", "")) == "Eclipse Verdict":
		var deadline := int(warning.get("resolveAt", 0))
		if deadline != _eclipse_deadline or not _eclipse_waiting:
			_begin_eclipse(deadline, live)
		return
	if live and special == "Eclipse Verdict":
		_resolve_eclipse()
		return
	if _eclipse_waiting or not live:
		_clear_eclipse()
	if not live:
		# Reconnect/replay shows authoritative health without replaying old attacks.
		_pending.clear()
		_clear_bolt()
		_play(&"idle")
		return
	if not special.is_empty():
		_pending.clear()
		_clear_bolt()
		match special:
			"Corruption Bolt": _play(&"corruption_bolt")
			"Shadow Lash": _play(&"shadow_lash")
			"Hollow Wail": _play(&"hollow_wail")
			"Soul Drain": _play(&"soul_drain")
			"Eclipse Verdict": _play(&"ravienna_eclipse")
		return
	if hp >= previous:
		return
	# Bound cosmetic backlog under simultaneous party strikes.
	if _pending.size() < 2:
		_pending.append(&"hit")
	if counter and _pending.size() < 3:
		_pending.append(&"shadow_lash" if phase >= 2 else &"corruption_bolt")
	if art.animation == &"idle" or not art.is_playing():
		_next_clip()

func _play(clip: StringName) -> void:
	art.play(clip, 1.0)
	art.set_frame_and_progress(0, 0.0)

func _next_clip() -> void:
	if _defeated:
		return
	_play(&"idle" if _pending.is_empty() else _pending.pop_front())

func _on_frame() -> void:
	if art.animation == &"ravienna_eclipse" and _eclipse_waiting:
		if art.frame == 3:
			_play_effect(cracks)
		if art.frame >= 9:
			art.pause()
		return
	if _defeated or art.animation != &"corruption_bolt" or art.frame != 5:
		return
	_clear_bolt()
	_bolt = preload("res://scenes/ui/combat/components/revienna_corruption_projectile.tscn").instantiate()
	portrait.add_child(_bolt)
	_bolt.position = rig.position + Vector2(-48, -88) * rig.scale
	_bolt_tween = create_tween()
	_bolt_tween.tween_property(_bolt, "position", Vector2(12, _bolt.position.y), 0.26)
	_bolt_tween.tween_callback(_clear_bolt)

func _clear_bolt() -> void:
	if _bolt_tween != null and _bolt_tween.is_valid():
		_bolt_tween.kill()
	_bolt_tween = null
	if is_instance_valid(_bolt):
		_bolt.queue_free()
	_bolt = null


func _play_effect(effect: AnimatedSprite2D) -> void:
	effect.show()
	effect.play()
	effect.set_frame_and_progress(0, 0.0)

func _begin_eclipse(deadline: int, live: bool) -> void:
	_pending.clear()
	_clear_bolt()
	_clear_eclipse()
	_eclipse_deadline = deadline
	_eclipse_waiting = true
	_play_effect(corona)
	art.play(&"ravienna_eclipse", 0.72)
	art.set_frame_and_progress(0, 0.0)
	if not live:
		# A recovery snapshot does not restart a server-owned countdown.
		_play_effect(cracks)
		art.frame = 9
		art.pause()

func _resolve_eclipse() -> void:
	_pending.clear()
	_clear_bolt()
	_eclipse_waiting = false
	_eclipse_deadline = 0
	art.play(&"ravienna_eclipse", 1.0)
	art.set_frame_and_progress(10, 0.0)
	_play_effect(cracks)
	_play_effect(eruption)
	_play_effect(corona)

func _clear_eclipse() -> void:
	_eclipse_waiting = false
	_eclipse_deadline = 0
	for fx in [cracks, corona, eruption]:
		fx.stop()
		fx.hide()
