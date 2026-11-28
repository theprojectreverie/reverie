extends CharacterBody2D
## Local art/physics preview only. Does not use the live player or account systems.
@onready var art: AnimatedSprite2D = $Artwork
@onready var ground: TileMapLayer = $"../City/DraftGround"
var facing := 0
var spawn_at := Vector2(0, 900)
func _physics_process(delta: float) -> void:
	var d := Vector2(float(Input.is_physical_key_pressed(KEY_D) or Input.is_physical_key_pressed(KEY_RIGHT))-float(Input.is_physical_key_pressed(KEY_A) or Input.is_physical_key_pressed(KEY_LEFT)),float(Input.is_physical_key_pressed(KEY_S) or Input.is_physical_key_pressed(KEY_DOWN))-float(Input.is_physical_key_pressed(KEY_W) or Input.is_physical_key_pressed(KEY_UP))).normalized()
	var speed := 235.0 if Input.is_physical_key_pressed(KEY_SHIFT) else 150.0
	velocity = d * speed
	var next := global_position + velocity * delta
	if ground.get_cell_source_id(ground.local_to_map(ground.to_local(next))) < 0:
		velocity = Vector2.ZERO
	var previous := global_position
	move_and_slide()
	if ground.get_cell_source_id(ground.local_to_map(ground.to_local(global_position))) < 0:
		global_position = previous
	if d.length_squared() > 0.01:
		facing = posmod(roundi((PI / 2.0 - d.angle()) / (PI / 4.0)), 8)
	var key := ("walk_" if global_position.distance_to(previous) > 0.1 else "idle_") + str(facing)
	if art.animation != key:
		art.play(key)
func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.physical_keycode == KEY_HOME:
		position = spawn_at
		reset_physics_interpolation()

