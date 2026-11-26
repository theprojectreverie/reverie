extends Interactable
signal challenge_requested
@onready var sprite: AnimatedSprite2D = $AnimatedSprite2D
func _ready() -> void:
	super._ready()
	enabled = false
	prompt = "Talk to companion"
	interaction_radius = 90.0
func unlock() -> void:
	enabled = true
	$Marker.show()
func _process(_delta: float) -> void:
	var player := get_tree().get_first_node_in_group("player") as Node2D
	if player == null:
		return
	var offset := player.global_position - global_position
	var direction := "front"
	if absf(offset.x) > absf(offset.y) * 0.65:
		direction = "left" if offset.x < 0.0 else "right"
	if sprite.animation != direction:
		sprite.play(direction)
# Short lateral walk on the authored entrance path. Only the approved side-facing
# walk sheet is available; mirror it for the other direction.
func walk_for_farewell(player_position: Vector2) -> void:
	enabled = false
	$Marker.hide()
	set_process(false)
	var side := 1.0 if player_position.x >= global_position.x else -1.0
	if absf(player_position.x - global_position.x) < 64.0:
		side = -side
	sprite.flip_h = side > 0.0
	sprite.play(&"walk_left")
	sprite.set_frame_and_progress(0, 0.0)
	var movement := create_tween()
	movement.tween_property(self, "position:x", position.x + side * 48.0, 1.0)
	await movement.finished
	sprite.flip_h = false
	sprite.play(&"front")

func interact() -> void:
	if can_interact():
		challenge_requested.emit()