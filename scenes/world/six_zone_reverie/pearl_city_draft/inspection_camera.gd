extends Camera2D
@export var pan_speed: float = 680.0
func _process(delta: float) -> void:
	var direction := Vector2(
		float(Input.is_physical_key_pressed(KEY_D) or Input.is_physical_key_pressed(KEY_RIGHT)) - float(Input.is_physical_key_pressed(KEY_A) or Input.is_physical_key_pressed(KEY_LEFT)),
		float(Input.is_physical_key_pressed(KEY_S) or Input.is_physical_key_pressed(KEY_DOWN)) - float(Input.is_physical_key_pressed(KEY_W) or Input.is_physical_key_pressed(KEY_UP)))
	position += direction.normalized() * pan_speed * delta / zoom.x
	position = position.clamp(Vector2(-2900, -100), Vector2(3200, 3100))
func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			zoom = Vector2.ONE * minf(zoom.x * 1.15, 1.5)
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			zoom = Vector2.ONE * maxf(zoom.x / 1.15, 0.15)
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_HOME:
		position = Vector2(0, 1450)
		zoom = Vector2(0.2, 0.2)

