extends Node2D
class_name SharedCharacterEffects

@onready var player: AnimationPlayer = $AnimationPlayer
@onready var owner_visual: ActorVisual = get_parent() as ActorVisual
@onready var slash_particles: CPUParticles2D = $SlashParticles
@onready var cast_particles: CPUParticles2D = $CastParticles
@onready var halo: Line2D = $ElementHalo
@onready var sigil: Line2D = $GroundSigil

var _last_state := -1

func _ready() -> void:
	visible = false
	slash_particles.emitting = false
	cast_particles.emitting = false

func _process(_delta: float) -> void:
	if owner_visual == null or owner_visual.animator == null or owner_visual.character_id == "kael" or owner_visual.character_id.begins_with("gerald") or owner_visual.character_id.begins_with("lilith") or owner_visual.character_id.begins_with("ravienna") or owner_visual.character_id.begins_with("cassien") or owner_visual.character_id.begins_with("mirene"):
		visible = false
		if _last_state != -1:
			player.stop()
			_clear_transient_particles()
			_last_state = -1
		return
	visible = true
	_apply_palette()
	var state := owner_visual.animator.state
	if state != _last_state:
		_last_state = state
		_play_state(state)

func _apply_palette() -> void:
	var accent: Color = owner_visual._accent
	var element_color: Color = UITheme.element_color(owner_visual.element)
	if element_color != UITheme.TEXT_DIM:
		accent = accent.lerp(element_color, 0.42)
	halo.default_color = accent
	sigil.default_color = accent.lerp(Color.WHITE, 0.58)

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
	if player.has_animation(clip):
		player.play(clip)
	if state == ActorVisual.S_ATTACK or state == ActorVisual.S_DAMAGE:
		_restart(slash_particles)
	elif state == ActorVisual.S_CAST:
		_restart(cast_particles)

func _restart(particles: CPUParticles2D) -> void:
	particles.emitting = false
	GraphicsSettings.prepare_combat_particles(particles)
	particles.restart()
	particles.emitting = true


func _clear_transient_particles() -> void:
	for particles in [slash_particles, cast_particles]:
		particles.emitting = false
		particles.restart()
		particles.emitting = false
