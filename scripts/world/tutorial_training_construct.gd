class_name TutorialTrainingConstruct
extends Node2D
## Reusable target scene. Presentation is authored in the scene; this component
## only exposes hit feedback to the tutorial coordinator.

signal struck(hit_kind: StringName)

@onready var sprite: Sprite2D = $Sprite
@onready var hit_flash: Sprite2D = $HitFlash

func receive_tutorial_hit(hit_kind: StringName) -> void:
	struck.emit(hit_kind)
	var tween := create_tween()
	tween.tween_property(self, "rotation", 0.08 if hit_kind == &"light" else 0.16, 0.07)
	tween.tween_property(self, "rotation", 0.0, 0.16)
	hit_flash.modulate.a = 0.78
	var flash := create_tween()
	flash.tween_property(hit_flash, "modulate:a", 0.0, 0.22)
