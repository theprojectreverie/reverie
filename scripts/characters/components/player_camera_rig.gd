class_name PlayerCameraRig
extends Camera2D
## Camera node owns player zoom controls and avatar framing.

const MIN_ZOOM := 0.28
@export_range(0.28, 1.85, 0.01) var scene_min_zoom: float = MIN_ZOOM
const MAX_ZOOM := 1.85
const ZOOM_RATE := 0.65
const WHEEL_STEP := 0.08
const GERALD_ZOOM_FACTOR := 1.0
const LOOKAHEAD_DISTANCE := 28.0
const LOOKAHEAD_VERTICAL := 0.6
const LOOKAHEAD_RATE := 5.0
const PORTRAIT_ASPECT_THRESHOLD := 0.85
const PORTRAIT_HORIZONTAL_OFFSET := 0.0
const PORTRAIT_VERTICAL_SCREEN_FRACTION := 0.10
const PORTRAIT_ZOOM_FACTOR := 1.2
const REFERENCE_MOVE_SPEED := 350.0

var _base_zoom: float = 1.1
var _avatar_id: String = "kael"
var _world_limit_left: int = -10000000
var _world_limit_top: int = -10000000
var _world_limit_right: int = 10000000
var _world_limit_bottom: int = 10000000
var _last_is_portrait: bool = false
var _follow_local_offset: Vector2 = Vector2.ZERO
var _has_world_bounds: bool = false


func _ready() -> void:
	_base_zoom = clampf(zoom.x, scene_min_zoom, MAX_ZOOM)
	_last_is_portrait = _is_portrait_viewport()
	_apply_zoom()
	# The world root uses non-uniform scale. Keep Camera2D in canvas/global
	# space and explicitly follow the player so its transform is not scaled twice.
	_follow_local_offset = position
	top_level = true
	sync_follow_target()
	make_current()


func sync_follow_target() -> void:
	var follow_target := get_parent() as Node2D
	if follow_target == null:
		return
	var global_offset := follow_target.global_transform.basis_xform(_follow_local_offset)
	global_position = follow_target.global_position + global_offset


func _process(delta: float) -> void:
	# Follow synchronization is owned by PlayerLocomotionComponent's physics tick.
	if Input.is_action_pressed("zoom_in"):
		set_base_zoom(_base_zoom - ZOOM_RATE * delta)
	if Input.is_action_pressed("zoom_out"):
		set_base_zoom(_base_zoom + ZOOM_RATE * delta)


func _unhandled_input(event: InputEvent) -> void:
	if not event is InputEventMouseButton or not event.pressed:
		return
	var mouse_event := event as InputEventMouseButton
	if mouse_event.button_index == MOUSE_BUTTON_WHEEL_UP:
		set_base_zoom(_base_zoom - WHEEL_STEP)
	elif mouse_event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
		set_base_zoom(_base_zoom + WHEEL_STEP)


func _is_portrait_viewport() -> bool:
	var viewport_size := get_viewport_rect().size
	return viewport_size.y > 0.0 and viewport_size.x / viewport_size.y < PORTRAIT_ASPECT_THRESHOLD


func set_world_bounds(bounds_min: Vector2, bounds_max: Vector2) -> void:
	_world_limit_left = floori(bounds_min.x)
	_world_limit_right = ceili(bounds_max.x)
	_world_limit_top = floori(bounds_min.y)
	_world_limit_bottom = ceili(bounds_max.y)
	_has_world_bounds = true
	_apply_offset_limit_compensation()


func _apply_offset_limit_compensation() -> void:
	if not _has_world_bounds:
		return
	# Camera2D applies offset after its world-edge clamp. Shift each limit by
	# the inverse current offset so responsive framing cannot reveal clear color.
	limit_left = floori(float(_world_limit_left) - offset.x)
	limit_right = ceili(float(_world_limit_right) - offset.x)
	limit_top = floori(float(_world_limit_top) - offset.y)
	limit_bottom = ceili(float(_world_limit_bottom) - offset.y)


func update_follow_offset(delta: float, move_velocity: Vector2, movement_ratio: float) -> void:
	var is_portrait := _is_portrait_viewport()
	if is_portrait != _last_is_portrait:
		_last_is_portrait = is_portrait
		_apply_zoom()
	# Express portrait framing relative to the visible view, not fixed world coordinates.
	var portrait_offset := get_viewport_rect().size.y * PORTRAIT_VERTICAL_SCREEN_FRACTION / maxf(zoom.y, 0.01)
	var target := Vector2(PORTRAIT_HORIZONTAL_OFFSET, portrait_offset) if is_portrait else Vector2.ZERO
	if move_velocity.length_squared() > 1.0:
		var direction := move_velocity.normalized()
		target += Vector2(direction.x, direction.y * LOOKAHEAD_VERTICAL) * LOOKAHEAD_DISTANCE * clampf(movement_ratio, 0.0, 1.0)
	offset = offset.lerp(target, 1.0 - exp(-LOOKAHEAD_RATE * delta))
	_apply_offset_limit_compensation()


func set_avatar_id(character_id: String) -> void:
	_avatar_id = character_id
	_apply_zoom()


func set_base_zoom(value: float) -> void:
	_base_zoom = clampf(value, scene_min_zoom, MAX_ZOOM)
	_apply_zoom()


func _apply_zoom() -> void:
	var avatar_factor := GERALD_ZOOM_FACTOR if _avatar_id == "gerald" else 1.0
	var aspect_factor := PORTRAIT_ZOOM_FACTOR if _last_is_portrait else 1.0
	zoom = Vector2.ONE * (_base_zoom * avatar_factor * aspect_factor)
