class_name ActorAnimationRuntimeComponent
extends Node
## Owns the per-frame animation runtime cadence for one ActorVisual instance.
## CharacterAnimator remains a pure state machine; ActorVisual retains its public API.

var visual: ActorVisual
# Default zero preserves the full update cadence for every local actor.
var presentation_interval := 0.0
var _presentation_elapsed := 0.0
var _next_presentation_interval := 0.0
var presentation_suppressed := false

func set_presentation_interval(seconds: float, phase: float = 0.0) -> void:
	var next := maxf(0.0, seconds)
	if is_equal_approx(next, presentation_interval):
		return
	presentation_interval = next
	# Only the first interval is shortened. Never inject artificial animation
	# time: the visual receives actual accumulated elapsed seconds.
	_next_presentation_interval = next * (1.0 - clampf(phase, 0.0, 0.99))


func set_presentation_suppressed(suppressed: bool) -> void:
	if suppressed == presentation_suppressed:
		return
	presentation_suppressed = suppressed
	if not suppressed and is_instance_valid(visual):
		# Catch the state clock up before presenting a newly visible actor.
		if _presentation_elapsed > 0.0:
			var elapsed := _presentation_elapsed
			_presentation_elapsed = 0.0
			visual.tick_animation(elapsed, false)
		visual.refresh_animation_presentation()

func bind(owner_visual: ActorVisual) -> void:
	visual = owner_visual


func _process(delta: float) -> void:
	if visual == null or not is_instance_valid(visual) or not visual.is_inside_tree():
		return
	_presentation_elapsed += delta
	if _presentation_elapsed + 0.000001 < _next_presentation_interval:
		return
	var elapsed := _presentation_elapsed
	_presentation_elapsed = 0.0
	_next_presentation_interval = presentation_interval
	visual.tick_animation(elapsed, not presentation_suppressed)
