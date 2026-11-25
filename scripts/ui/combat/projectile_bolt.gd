extends Node2D
class_name ProjectileBolt

@onready var art: Node2D = $Art
@onready var trail: Line2D = $Art/Trail
@onready var core: Line2D = $Art/Core
@onready var head: Polygon2D = $Art/Head
@onready var sparks: CPUParticles2D = $TrailSparks
@onready var animation_player: AnimationPlayer = $AnimationPlayer

func _ready() -> void:
	animation_player.animation_finished.connect(_on_animation_finished)
	var shared_library := animation_player.get_animation_library(&"")
	if shared_library != null:
		var local_library := shared_library.duplicate(true) as AnimationLibrary
		animation_player.remove_animation_library(&"")
		animation_player.add_animation_library(&"", local_library)
	sparks.emitting = false

func launch(from: Vector2, to: Vector2, color: Color, duration: float = 0.26) -> void:
	position = from
	var direction := (to - from).normalized()
	if direction.length_squared() < 0.001:
		direction = Vector2.RIGHT
	rotation = direction.angle()
	trail.default_color = Color(color.r, color.g, color.b, 0.88)
	core.default_color = color.lightened(0.48)
	head.color = color.lightened(0.32)
	sparks.color = color.lightened(0.24)
	var flight := animation_player.get_animation(&"flight")
	var position_track := flight.find_track(NodePath(".:position"), Animation.TYPE_VALUE)
	if position_track >= 0:
		flight.track_set_key_value(position_track, 0, from)
		flight.track_set_key_value(position_track, 1, to)
	animation_player.play(&"flight")
	animation_player.speed_scale = 0.32 / maxf(0.08, duration)
	sparks.restart()
	sparks.emitting = true

func _on_animation_finished(animation_name: StringName) -> void:
	if animation_name == &"flight":
		queue_free()
