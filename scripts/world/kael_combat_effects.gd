extends Node2D
class_name KaelCombatEffects

@onready var player: AnimationPlayer = $AnimationPlayer
@onready var owner_visual: ActorVisual = get_parent() as ActorVisual
@onready var slash_sparks: CPUParticles2D = $SlashSparks
@onready var impact_sparks: CPUParticles2D = $ImpactSparks
@onready var cast_embers: CPUParticles2D = $CastEmbers

var _last_state := -1

func _ready() -> void:
	visible = false
	for particles in [slash_sparks, impact_sparks, cast_embers]:
		particles.emitting = false

func _process(_delta: float) -> void:
	if owner_visual == null or owner_visual.animator == null or owner_visual.character_id != "kael":
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
	if player.has_animation(clip):
		player.play(clip)
	if state == ActorVisual.S_ATTACK:
		_restart(slash_sparks)
	elif state == ActorVisual.S_CAST:
		_restart(cast_embers)
	elif state == ActorVisual.S_DAMAGE:
		_restart(impact_sparks)

func _restart(particles: CPUParticles2D) -> void:
	particles.emitting = false
	particles.restart()
	particles.emitting = true


func _clear_transient_particles() -> void:
	for particles in [slash_sparks, impact_sparks, cast_embers]:
		particles.emitting = false
		particles.restart()
		particles.emitting = false
