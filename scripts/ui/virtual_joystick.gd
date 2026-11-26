class_name TouchJoystick
extends Control
## On-screen joystick for touch devices. It writes into TouchInput so the player
## controller never needs to know whether input came from a thumb or a keyboard.
## Visual composition is authored as editable scene nodes; input/calculation stays in script.

const RADIUS := 70.0
const KNOB_RADIUS := 30.0

var _active_index: int = -1
var _center: Vector2 = Vector2.ZERO
var _knob_pos: Vector2 = Vector2.ZERO
var _pressed: bool = false

@onready var _base_node: Node2D = get_node_or_null("Base") as Node2D
@onready var _outer_glow: Polygon2D = get_node_or_null("Base/OuterGlow") as Polygon2D
@onready var _base_fill: Polygon2D = get_node_or_null("Base/BaseFill") as Polygon2D
@onready var _base_ring: Line2D = get_node_or_null("Base/BaseRing") as Line2D
@onready var _knob_node: Node2D = get_node_or_null("Knob") as Node2D
@onready var _knob_fill: Polygon2D = get_node_or_null("Knob/KnobFill") as Polygon2D
@onready var _knob_ring: Line2D = get_node_or_null("Knob/KnobRing") as Line2D
@onready var _knob_dot: Polygon2D = get_node_or_null("Knob/KnobDot") as Polygon2D


func _ready() -> void:
	custom_minimum_size = Vector2(170, 170)
	mouse_filter = Control.MOUSE_FILTER_STOP
	_center = size * 0.5
	_knob_pos = _center
	set_process(false)
	TouchInput.released.connect(_reset_capture)
	_refresh_visuals()


func _notification(what: int) -> void:
	if what == NOTIFICATION_VISIBILITY_CHANGED and not is_visible_in_tree() and is_node_ready():
		if _pressed:
			_release()
	if what == NOTIFICATION_RESIZED:
		_center = size * 0.5
		if not _pressed:
			_knob_pos = _center
		_refresh_visuals()


func _input(event: InputEvent) -> void:
	if _active_index < 0:
		return
	if event is InputEventScreenTouch and event.index == _active_index and (not event.pressed or event.canceled):
		_release()
		get_viewport().set_input_as_handled()
	elif event is InputEventScreenDrag and event.index == _active_index:
		_update_knob(get_global_transform_with_canvas().affine_inverse() * event.position)
		get_viewport().set_input_as_handled()

func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouse and (event.device == InputEvent.DEVICE_ID_EMULATION or _active_index >= 0):
		accept_event()
		return
	if event is InputEventScreenTouch:
		if event.pressed and not event.canceled and _active_index < 0:
			_active_index = event.index
			_pressed = true
			_update_knob(event.position)
			accept_event()
		elif not event.pressed and event.index == _active_index:
			_release()
			accept_event()
	elif event is InputEventScreenDrag and event.index == _active_index:
		_update_knob(event.position)
		accept_event()
	elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			_pressed = true
			_update_knob(event.position)
		else:
			_release()
		accept_event()
	elif event is InputEventMouseMotion and _pressed:
		_update_knob(event.position)
		accept_event()


func _update_knob(local_position: Vector2) -> void:
	var offset := local_position - _center
	if offset.length() > RADIUS:
		offset = offset.normalized() * RADIUS
	_knob_pos = _center + offset
	var value := offset / RADIUS
	var strength := value.length()
	# Small dead zone removes thumb jitter without reducing full-speed reach.
	TouchInput.set_move_vector(Vector2.ZERO if strength <= 0.12 else value.normalized() * ((strength - 0.12) / 0.88))
	_update_knob_position()


func _release() -> void:
	TouchInput.release()

func _reset_capture() -> void:
	_active_index = -1
	_pressed = false
	_knob_pos = _center
	_update_knob_position()


func _refresh_visuals() -> void:
	if _outer_glow:
		_outer_glow.polygon = _circle_poly(Vector2.ZERO, RADIUS + 10.0, 40)
	if _base_fill:
		_base_fill.polygon = _circle_poly(Vector2.ZERO, RADIUS, 40)
	if _base_ring:
		_base_ring.points = _ring_points(Vector2.ZERO, RADIUS, 40)
	if _knob_fill:
		_knob_fill.polygon = _circle_poly(Vector2.ZERO, KNOB_RADIUS, 32)
	if _knob_ring:
		_knob_ring.points = _ring_points(Vector2.ZERO, KNOB_RADIUS, 32)
	if _knob_dot:
		_knob_dot.polygon = _circle_poly(Vector2.ZERO, KNOB_RADIUS * 0.32, 16)
	if _base_node:
		_base_node.position = _center
	_update_knob_position()


func _update_knob_position() -> void:
	if _knob_node:
		_knob_node.position = _knob_pos


func _circle_poly(center: Vector2, radius: float, segments: int) -> PackedVector2Array:
	var pts := PackedVector2Array()
	for i in segments:
		var a := TAU * float(i) / float(segments)
		pts.append(center + Vector2(cos(a), sin(a)) * radius)
	return pts


func _ring_points(center: Vector2, radius: float, segments: int) -> PackedVector2Array:
	var pts := _circle_poly(center, radius, segments)
	if pts.size() > 0:
		pts.append(pts[0])
	return pts
