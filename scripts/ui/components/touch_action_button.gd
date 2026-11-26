extends Button
## Independent touch presses, including a second thumb while joystick is held.
func _input(event: InputEvent) -> void:
	if not is_visible_in_tree() or disabled:
		return
	if event is InputEventScreenTouch and event.pressed and not event.canceled and get_global_rect().has_point(event.position):
		var player := get_tree().get_first_node_in_group("player") as Player
		if player == null or not player.input_enabled or player.network_recovery_paused:
			return
		get_viewport().set_input_as_handled()
		pressed.emit()
	elif event is InputEventMouseButton and event.device == InputEvent.DEVICE_ID_EMULATION and get_global_rect().has_point(event.position):
		get_viewport().set_input_as_handled()
