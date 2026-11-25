class_name RemotePlayerAvatar
extends Node2D
## Lightweight presentation-only remote avatar. It has no collision or camera.

const ACTOR_SCENE: PackedScene = preload("res://scenes/characters/actor_visual.tscn")
var player_id := ""
var display_name := "Wanderer"
var target_position := Vector2.ZERO
var visual: ActorVisual
var name_label: Label
var _last_direction := Vector2.DOWN

func _ready() -> void:
	visual = ACTOR_SCENE.instantiate() as ActorVisual
	visual.name = "ActorVisual"
	add_child(visual)
	# Until profiles expose a validated selected-character ID, keep remote
	# players neutral instead of depicting every connected player as Kael.
	visual.setup({}, ActorVisual.Kind.HUMAN, "remote_player")
	name_label = Label.new()
	name_label.name = "NameLabel"
	name_label.text = display_name
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_label.position = Vector2(-64, -104)
	name_label.size = Vector2(128, 24)
	name_label.add_theme_font_size_override("font_size", 12)
	name_label.add_theme_color_override("font_color", Color("#f1e7d2"))
	name_label.add_theme_color_override("font_shadow_color", Color("#211a2b"))
	name_label.add_theme_constant_override("shadow_offset_x", 1)
	name_label.add_theme_constant_override("shadow_offset_y", 1)
	add_child(name_label)
	position = target_position

func configure(id: String, label: String, spawn_position: Vector2) -> void:
	player_id = id
	display_name = label if not label.is_empty() else "Wanderer"
	target_position = spawn_position
	position = spawn_position
	if name_label != null:
		name_label.text = display_name

func set_authoritative_position(next_position: Vector2) -> void:
	var delta := next_position - target_position
	if delta.length_squared() > 0.01:
		_last_direction = delta.normalized()
		target_position = next_position
		if visual != null:
			visual.set_move_direction(_last_direction)
			visual.walking = true
			visual.play(ActorVisual.S_WALK)
	else:
		target_position = next_position

func _process(delta: float) -> void:
	position = position.lerp(target_position, 1.0 - exp(-14.0 * delta))
	if visual != null and position.distance_squared_to(target_position) < 3.0:
		visual.walking = false
		visual.play(ActorVisual.S_IDLE)
