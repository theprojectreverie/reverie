class_name BattlefieldImpactEffectsComponent
extends Control
## Owns transient impact particles and floating combat-number presentation.

var battlefield: Battlefield


func bind(owner: Battlefield) -> void:
	battlefield = owner
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE


## A floating damage / heal number above an actor.
func spawn_damage_number(actor: BattlefieldActor, text: String, color: Color,
		delay: float = 0.0) -> void:
	if battlefield == null or not is_instance_valid(battlefield) or battlefield._stage == null:
		return
	var owner_screen := battlefield.get_parent() as CombatScreen
	if owner_screen != null and owner_screen._resolved:
		return
	if actor == null or not is_instance_valid(actor) or not actor.is_inside_tree():
		return
	var label := preload("res://scenes/ui/combat/components/floating_combat_number.tscn").instantiate() as Label
	label.text = text
	label.add_theme_font_size_override("font_size", Battlefield.DAMAGE_FONT)
	label.add_theme_color_override("font_color", color)
	label.add_theme_color_override("font_outline_color", Color(0.01, 0.02, 0.05, 0.95))
	label.add_theme_constant_override("outline_size", 6)
	label.z_index = 60
	battlefield._stage.add_child(label)
	var start: Vector2 = actor.position + Vector2(-28.0, -74.0 * actor.visual.visual_scale)
	label.position = start
	label.call("play_number", delay, text.contains("!"))


## The elemental burst at the impact point.
func spawn_elemental_burst(pos: Vector2, element: String) -> void:
	_spawn_elemental_burst(null, pos, element)


func spawn_attack_elemental_burst(owner: BattlefieldActor, pos: Vector2, element: String) -> void:
	_spawn_elemental_burst(owner, pos, element)


func _spawn_elemental_burst(owner: BattlefieldActor, pos: Vector2, element: String) -> void:
	var color := UITheme.element_color(element)
	if color == UITheme.TEXT_DIM:
		color = Color(0.85, 0.85, 0.9)
	var particles := preload("res://scenes/ui/combat/components/elemental_burst.tscn").instantiate() as CPUParticles2D
	GraphicsSettings.prepare_combat_particles(particles)
	particles.emission_shape = CPUParticles2D.EMISSION_SHAPE_SPHERE
	particles.color = color
	particles.z_index = 35
	particles.position = pos
	add_child(particles)
	if owner != null and is_instance_valid(owner):
		owner.track_attack_effect(particles)
	particles.finished.connect(particles.queue_free)
	particles.emitting = true
	if owner != null and is_instance_valid(owner):
		owner.release_attack_effect(particles)


## Reusable authored slash/ring impact at the resolved damage position.
func spawn_hit_effect(target: BattlefieldActor, source: BattlefieldActor, color: Color, strength: float = 1.0) -> void:
	if target == null or not is_instance_valid(target) or battlefield == null or battlefield._stage == null:
		return
	var effect := preload("res://scenes/ui/combat/components/battle_hit_effect.tscn").instantiate() as Node2D
	var direction := Vector2.RIGHT
	if source != null and is_instance_valid(source):
		direction = target.position - source.position
	effect.position = target.position + Vector2(0.0, -22.0 * target.visual.visual_scale)
	effect.z_index = 36
	battlefield._stage.add_child(effect)
	effect.call("play_impact", direction, color, strength)

