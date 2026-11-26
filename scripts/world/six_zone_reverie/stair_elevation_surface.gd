extends Node2D
## A projected 2.5D staircase. Body coordinates remain at visible foot contact;
## logical ground coordinates and height are tracked separately.
@export var rise: float = 112.0
@export var stair_speed: float = 0.72
@export var top_half_width: float = 110.0
@export var bottom_half_width: float = 205.0
@export var upper_outline: PackedVector2Array
@onready var foot: Marker2D = $Foot
@onready var landing: Marker2D = $Landing
var actor: CharacterBody2D
var height: float = 0.0

func _ready() -> void:
	process_physics_priority = 10
	add_to_group("elevation_surface")
	
func ramp_progress(point: Vector2) -> float:
	var local := to_local(point)
	return clampf((foot.position.y - local.y) / maxf(1.0, foot.position.y - landing.position.y), 0.0, 1.0)

func is_on_ramp(point: Vector2) -> bool:
	var local := to_local(point)
	if local.y < landing.position.y or local.y > foot.position.y:
		return false
	var width := lerpf(bottom_half_width, top_half_width, ramp_progress(point))
	return absf(local.x - foot.position.x) <= width

func elevation_at(point: Vector2) -> float:
	if is_on_ramp(point):
		return ramp_progress(point) * rise
	if Geometry2D.is_point_in_polygon(to_local(point), upper_outline):
		return rise
	return 0.0

func project_motion(point: Vector2, motion: Vector2) -> Vector2:
	if not is_on_ramp(point):
		return motion
	# Vertical screen travel includes logical ground travel plus the change in height.
	var span := foot.position.y - landing.position.y
	var projection := span / maxf(1.0, span - rise)
	return Vector2(motion.x, motion.y * projection) * stair_speed

func _physics_process(_delta: float) -> void:
	if not is_instance_valid(actor):
		actor = get_tree().get_first_node_in_group("player") as CharacterBody2D
	if not is_instance_valid(actor):
		return
	height = elevation_at(actor.global_position)
	actor.set_meta("surface_elevation", height)
	actor.set_meta("logical_ground_position", actor.global_position + Vector2(0, height))
