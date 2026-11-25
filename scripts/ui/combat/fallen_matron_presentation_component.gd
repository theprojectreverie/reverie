class_name FallenMatronPresentationComponent
extends Node2D
## Owns the Fallen Matron's bespoke cutout, corruption phases and authored reactions.

const PHASE_HEIGHTS := [528.0, 386.0, 400.0]
const ART_PATHS := [
	"res://assets/enemies/fallen_matron/phase_1.png",
	"res://assets/enemies/fallen_matron/phase_2.png",
	"res://assets/enemies/fallen_matron/phase_3.png"
]

var _art: Sprite2D
var _motes: CPUParticles2D
var _unit: Combatant
var _phase := 0
var _home := Vector2(0, -96)
var _animation_player: AnimationPlayer
var active := false
var dead := false


func _ready() -> void:
	_art = get_node_or_null("Art") as Sprite2D
	_motes = get_node_or_null("CorruptionMotes") as CPUParticles2D
	_animation_player = get_node_or_null("AnimationPlayer") as AnimationPlayer
	if _art == null or _motes == null or _animation_player == null:
		push_error("FallenMatronPresentation requires authored Art, CorruptionMotes and AnimationPlayer children.")
		return
	_animation_player.animation_finished.connect(_on_animation_finished)
	_art.visible = false
	_motes.visible = false
	_motes.emitting = false


func configure(unit: Combatant, actor_visual: ActorVisual) -> bool:
	_unit = unit
	active = false
	dead = false
	if unit == null or unit.def_id != "fallen_matron" or _art == null or _motes == null:
		return false
	if not ResourceLoader.exists(ART_PATHS[0]):
		return false
	var texture := load(ART_PATHS[0]) as Texture2D
	if texture == null:
		return false
	_art.texture = texture
	_art.position = _home
	_art.scale = Vector2.ONE * (180.0 / PHASE_HEIGHTS[0])
	_art.visible = true
	_motes.visible = true
	_motes.emitting = true
	active = true
	if actor_visual != null:
		actor_visual.visible = false
	refresh_phase(unit.hp_ratio())
	_animation_player.play("idle")
	return true


func refresh_phase(hp_ratio: float) -> void:
	if not active or _art == null or dead:
		return
	var next_phase := 1
	if hp_ratio <= 0.33:
		next_phase = 3
	elif hp_ratio <= 0.66:
		next_phase = 2
	if next_phase == _phase:
		return
	var previous_phase := _phase
	_phase = next_phase
	var texture := load(ART_PATHS[_phase - 1]) as Texture2D
	if texture != null:
		_art.texture = texture
	_home = Vector2(0, -96)
	_art.position = _home
	_art.scale = Vector2.ONE * (180.0 / PHASE_HEIGHTS[_phase - 1])
	_art.modulate = Color.WHITE if _phase == 1 else Color(1.04, 0.94, 1.12, 1.0) if _phase == 2 else Color(1.12, 0.82, 1.22, 1.0)
	if previous_phase > 0:
		_spawn_phase_burst()
		_animation_player.play("phase_change")


func _spawn_phase_burst() -> void:
	var burst := preload("res://scenes/ui/combat/components/matron_phase_burst.tscn").instantiate() as CPUParticles2D
	burst.amount = 42 if _phase == 3 else 30
	burst.initial_velocity_max = 125.0 if _phase == 3 else 90.0
	burst.color = Color("#ed72ff") if _phase == 3 else Color("#b96cff")
	burst.position = _home + Vector2(0, -55)
	add_child(burst)
	burst.finished.connect(burst.queue_free)
	burst.emitting = true


func update_idle(_pulse: float, _hit_shake: float, _bob: float, is_dead: bool) -> void:
	if not active or is_dead or dead or _art == null:
		return
	if not _animation_player.is_playing():
		_animation_player.play("idle")


func take_hit() -> void:
	if not active or _art == null or dead:
		return
	_animation_player.play("hit")


func play_attack() -> void:
	if not active or _art == null or dead:
		return
	_animation_player.play("attack")


func play_death() -> void:
	if not active or _art == null or dead:
		return
	dead = true
	_motes.emitting = false
	_animation_player.play("death")


func _on_animation_finished(animation_name: StringName) -> void:
	if animation_name != &"death" and active and not dead:
		_animation_player.play("idle")


func get_phase() -> int:
	return _phase
