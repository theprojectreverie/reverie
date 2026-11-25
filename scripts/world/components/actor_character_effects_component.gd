class_name ActorCharacterEffectsComponent
extends Node2D
## Compatibility binding point; character VFX live in reusable authored scenes.

var visual: ActorVisual


func bind(owner_visual: ActorVisual) -> void:
	visual = owner_visual
	position = Vector2.ZERO
	z_index = 2
