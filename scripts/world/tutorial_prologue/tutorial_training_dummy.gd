class_name TutorialTrainingDummy
extends Node2D
## Editor-authored sparring dummy with small hit reactions for the opening lesson.

var _reaction_tween: Tween


func play_light_hit(hit_number: int) -> void:
	_play_reaction(0.07 if hit_number % 2 == 0 else -0.07)


func play_heavy_hit() -> void:
	_play_reaction(0.16)


func _play_reaction(amount: float) -> void:
	if _reaction_tween != null and _reaction_tween.is_running():
		_reaction_tween.kill()
	rotation = amount
	_reaction_tween = create_tween()
	_reaction_tween.tween_property(self, "rotation", 0.0, 0.16).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

signal world_struck(heavy: bool)
var defeated := false

func _ready() -> void:
	add_to_group("world_action_targets")

func receive_world_hit(amount: float) -> void:
	if amount >= 40.0:
		play_heavy_hit()
		world_struck.emit(true)
	else:
		play_light_hit(1)
		world_struck.emit(false)