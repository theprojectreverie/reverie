class_name KaelCinematicInputComponent
extends Node
## Owns touch/mouse input and the authored playback controls.

signal advance_requested
signal auto_play_changed(enabled: bool)
signal skip_requested

var _owner_control: Control
var _auto_button: Button
var _skip_button: Button
var _auto_play := false

func bind(owner: Control) -> bool:
	_owner_control = owner
	_auto_button = owner.get_node_or_null("AutoPlayButton") as Button
	_skip_button = owner.get_node_or_null("SkipButton") as Button
	if _auto_button == null or _skip_button == null:
		push_error("[KaelInput] Auto Play and Skip buttons must be authored scene nodes.")
		return false
	_auto_button.toggle_mode = true
	_auto_button.button_pressed = false
	_auto_button.text = "Auto Play: Off"
	_auto_button.toggled.connect(_on_auto_toggled)
	_skip_button.pressed.connect(skip_requested.emit)
	set_process_input(true)
	return true

func _input(event: InputEvent) -> void:
	if _auto_play:
		return
	var tapped := false
	var tap_position := Vector2.ZERO
	if event is InputEventScreenTouch:
		var touch := event as InputEventScreenTouch
		tapped = touch.pressed
		tap_position = touch.position
	elif event is InputEventMouseButton:
		var mouse := event as InputEventMouseButton
		tapped = mouse.button_index == MOUSE_BUTTON_LEFT and mouse.pressed
		tap_position = mouse.position
	if not tapped or _is_playback_control_tap(tap_position):
		return
	advance_requested.emit()
	get_viewport().set_input_as_handled()

func _is_playback_control_tap(position: Vector2) -> bool:
	# Input is observed before GUI dispatch so taps anywhere on the artwork
	# advance reliably, while the two authored buttons retain their own actions.
	return _auto_button.get_global_rect().has_point(position) or _skip_button.get_global_rect().has_point(position)

func _on_auto_toggled(enabled: bool) -> void:
	_auto_play = enabled
	_auto_button.text = "Auto Play: On" if enabled else "Auto Play: Off"
	auto_play_changed.emit(enabled)
