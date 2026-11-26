class_name ActorAnimationRuntimeComponent
extends Node
## Owns the per-frame animation runtime cadence for one ActorVisual instance.
## CharacterAnimator remains a pure state machine; ActorVisual retains its public API.

var visual: ActorVisual
# Default zero preserves the full update cadence for every local actor.
var presentation_interval := 0.0
var _presentation_elapsed := 0.0

func set_presentation_interval(seconds: float) -> void:
	presentation_interval = maxf(0.0, seconds)


func bind(owner_visual: ActorVisual) -> void:
	visual = owner_visual


func _process(delta: float) -> void:
	if visual == null or not is_instance_valid(visual) or not visual.is_inside_tree():
		return
	_presentation_elapsed += delta
	if _presentation_elapsed < presentation_interval:
		return
	var elapsed := _presentation_elapsed
	_presentation_elapsed = 0.0
	visual.tick_animation(elapsed)
