class_name WaterSurfaceComponent
extends Node2D
## Reusable configurable water presentation component. Geometry and motion are scene-authored.

@export var water_color: Color = Color(0.25, 0.55, 0.75, 0.75)
@export_range(0.05, 3.0, 0.05) var flow_speed: float = 0.4
@export var ripple_enabled: bool = true
@export_range(0.5, 4.0, 0.1) var wave_amplitude: float = 1.5

@onready var sprite: Sprite2D = get_node_or_null("Sprite2D") as Sprite2D
@onready var ripple_a: Line2D = get_node_or_null("RippleA") as Line2D
@onready var ripple_b: Line2D = get_node_or_null("RippleB") as Line2D
@onready var animation_player: AnimationPlayer = get_node_or_null("AnimationPlayer") as AnimationPlayer


func _ready() -> void:
	if sprite != null:
		sprite.modulate = water_color
	_apply_ripple_style()
	_apply_ripple_state()


func set_ripple_enabled(value: bool) -> void:
	ripple_enabled = value
	_apply_ripple_state()


func set_flow_speed(value: float) -> void:
	flow_speed = clampf(value, 0.05, 3.0)
	if animation_player != null and animation_player.is_playing():
		animation_player.speed_scale = flow_speed


func set_wave_amplitude(value: float) -> void:
	wave_amplitude = clampf(value, 0.5, 4.0)
	if ripple_a != null:
		ripple_a.width = 2.0 * wave_amplitude
	if ripple_b != null:
		ripple_b.width = 1.5 * wave_amplitude


func _apply_ripple_state() -> void:
	if animation_player == null:
		_set_ripples_visible(false)
		return
	if ripple_enabled and animation_player.has_animation("ripple"):
		_set_ripples_visible(true)
		animation_player.speed_scale = clampf(flow_speed, 0.05, 3.0)
		if not animation_player.is_playing() or animation_player.current_animation != &"ripple":
			animation_player.play("ripple")
	else:
		animation_player.stop()
		_set_ripples_visible(false)


func _apply_ripple_style() -> void:
	var tint := Color(water_color.r, water_color.g, water_color.b, 1.0)
	if ripple_a != null:
		ripple_a.default_color = tint.lightened(0.35)
	if ripple_b != null:
		ripple_b.default_color = tint.lightened(0.55)
	set_wave_amplitude(wave_amplitude)


func _set_ripples_visible(value: bool) -> void:
	if ripple_a != null:
		ripple_a.visible = value
	if ripple_b != null:
		ripple_b.visible = value
