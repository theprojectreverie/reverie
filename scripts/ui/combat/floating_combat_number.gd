extends Label
## Reusable floating damage/healing number with scene-authored motion.

signal finished

@onready var animation_player: AnimationPlayer = $AnimationPlayer


func play_number(delay: float = 0.0, critical: bool = false) -> void:
	if delay > 0.0:
		await get_tree().create_timer(delay).timeout
	if not is_inside_tree():
		return
	scale = Vector2(1.5, 1.5) if critical else Vector2.ONE
	var clip := animation_player.get_animation("float")
	clip.track_set_key_value(0, 0, position.y)
	clip.track_set_key_value(0, 1, position.y - 54.0)
	clip.track_set_key_value(2, 0, scale)
	animation_player.play("float")
	await animation_player.animation_finished
	finished.emit()
	queue_free()