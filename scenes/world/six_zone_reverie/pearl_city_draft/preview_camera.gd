extends Camera2D
## Isolated visual review camera. No account or quest actions.
func _process(delta: float) -> void:
	var direction := Vector2(float(Input.is_physical_key_pressed(KEY_D) or Input.is_physical_key_pressed(KEY_RIGHT))-float(Input.is_physical_key_pressed(KEY_A) or Input.is_physical_key_pressed(KEY_LEFT)), float(Input.is_physical_key_pressed(KEY_S) or Input.is_physical_key_pressed(KEY_DOWN))-float(Input.is_physical_key_pressed(KEY_W) or Input.is_physical_key_pressed(KEY_UP)))
	position += direction.normalized() * 700.0 * delta / zoom.x
	position = position.clamp(Vector2(-3100, -100), Vector2(3400, 3100))
func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			zoom = Vector2.ONE * clampf(zoom.x * 1.15, 0.18, 2.0)
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			zoom = Vector2.ONE * clampf(zoom.x / 1.15, 0.18, 2.0)
	if event is InputEventKey and event.pressed and not event.echo:
		if event.physical_keycode == KEY_HOME:
			position = Vector2(0, 1450)
			zoom = Vector2(0.25, 0.25)

