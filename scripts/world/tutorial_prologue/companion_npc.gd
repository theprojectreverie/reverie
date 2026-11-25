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
func interact() -> void:
	if can_interact():
		challenge_requested.emit()