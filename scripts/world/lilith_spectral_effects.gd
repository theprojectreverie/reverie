extends Node2D
class_name LilithSpectralEffects
@onready var player: AnimationPlayer = $AnimationPlayer
@onready var owner_visual: ActorVisual = get_parent() as ActorVisual
@onready var wisps: CPUParticles2D = $WispParticles
@onready var sparks: CPUParticles2D = $AttackSparks
var _last_state := -1
func _ready() -> void:
	visible = false
	wisps.emitting = false
	sparks.emitting = false
func _process(_delta: float) -> void:
	if owner_visual == null or owner_visual.animator == null or owner_visual.character_id != "lilith":
		visible = false
		return
	var state := owner_visual.animator.state
	if state != _last_state:
		_last_state = state
		_play_state(state)
func _play_state(state: int) -> void:
	if state in [ActorVisual.S_DAMAGE, ActorVisual.S_DEFEAT, ActorVisual.S_VICTORY]:
		_clear_transient_particles()
	var clip: StringName = &"idle"
	match state:
		ActorVisual.S_WALK: clip = &"walk"
		ActorVisual.S_RUN: clip = &"run"
		ActorVisual.S_ATTACK: clip = &"attack"
		ActorVisual.S_INTERACT: clip = &"interact"
		ActorVisual.S_DAMAGE: clip = &"damage"
		ActorVisual.S_VICTORY: clip = &"victory"
		ActorVisual.S_DEFEAT: clip = &"defeat"
		ActorVisual.S_CAST: clip = &"cast"
	visible = true
	if player.has_animation(clip): player.play(clip)
	if state == ActorVisual.S_ATTACK or state == ActorVisual.S_DAMAGE: _restart(sparks)
	elif state == ActorVisual.S_CAST: _restart(wisps)
func _restart(p: CPUParticles2D) -> void:
	p.emitting = false
	p.restart()
	p.emitting = true


func _clear_transient_particles() -> void:
	for particles in [wisps, sparks]:
		particles.emitting = false
		particles.restart()
		particles.emitting = false
