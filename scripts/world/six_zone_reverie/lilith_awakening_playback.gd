extends Node2D
signal awakened
@onready var player: AnimationPlayer = $AnimationPlayer
func _ready() -> void:
	player.animation_finished.connect(_on_finished)
func _on_finished(clip: StringName) -> void:
	if clip != &"spiritual_transformation":
		return
	player.play(&"floating_idle")
	awakened.emit()

