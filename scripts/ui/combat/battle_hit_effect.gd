extends Node2D
## Reusable authored strike impact. Presentation only; never applies damage.

@onready var art: Node2D = $Art
@onready var slash: Line2D = $Art/Slash
@onready var core: Line2D = $Art/Core
@onready var ring: Line2D = $Art/Ring
@onready var spark_a: Line2D = $Art/SparkA
@onready var spark_b: Line2D = $Art/SparkB
@onready var spark_c: Line2D = $Art/SparkC
@onready var spark_d: Line2D = $Art/SparkD
@onready var animation_player: AnimationPlayer = $AnimationPlayer


func _ready() -> void:
	animation_player.animation_finished.connect(_on_animation_finished)


func play_impact(direction: Vector2, color: Color, strength: float = 1.0) -> void:
	var facing := direction.normalized() if direction.length_squared() > 0.001 else Vector2.RIGHT
	art.rotation = facing.angle()
	var accent := color.lightened(0.42)
	slash.default_color = Color(color.r, color.g, color.b, 0.94)
	core.default_color = Color(accent.r, accent.g, accent.b, 0.96)
	ring.default_color = Color(color.r, color.g, color.b, 0.78)
	for spark in [spark_a, spark_b, spark_c, spark_d]:
		spark.default_color = Color(accent.r, accent.g, accent.b, 0.94)
	art.scale = Vector2.ONE * clampf(strength, 0.65, 1.6)
	art.modulate = Color.WHITE
	var clip: StringName = &"critical" if strength >= 1.3 and animation_player.has_animation(&"critical") else &"impact"
	animation_player.play(clip)


func _on_animation_finished(animation_name: StringName) -> void:
	if animation_name in [&"impact", &"critical"]:
		queue_free()
