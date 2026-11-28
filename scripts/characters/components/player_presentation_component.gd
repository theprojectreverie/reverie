class_name PlayerPresentationComponent
extends Node
## Owns player visual-node setup, water presentation and one-shot/event cues.

const HERO_PALETTE := {
	"hair": "#5a3a2a",
	"primary": "#2f4a6b",
	"secondary": "#c9a45a",
	"accent": "#7fe3e0",
	"skin": "#f0cbb0",
}

var actor: Node2D
const WADE_SHADER = preload("res://shaders/player_wade.gdshader")
var _wade_material: ShaderMaterial
var _dry_material: Material
var _wade_sprite: Sprite2D


func _ready() -> void:
	actor = get_parent() as Node2D
	if not EventBus.battle_finished.is_connected(_on_battle_finished):
		EventBus.battle_finished.connect(_on_battle_finished)
	if not EventBus.encounter_requested.is_connected(_on_encounter_requested):
		EventBus.encounter_requested.connect(_on_encounter_requested)


func _exit_tree() -> void:
	if EventBus.battle_finished.is_connected(_on_battle_finished):
		EventBus.battle_finished.disconnect(_on_battle_finished)
	if EventBus.encounter_requested.is_connected(_on_encounter_requested):
		EventBus.encounter_requested.disconnect(_on_encounter_requested)


func configure_visual_nodes() -> ActorVisual:
	if actor == null:
		push_error("PlayerPresentationComponent requires a Player parent")
		return null
	var visual := actor.get_node_or_null("ActorVisual") as ActorVisual
	var name_label := actor.get_node_or_null("NameLabel") as Label
	var glow := actor.get_node_or_null("PersonalGlow") as PlayerPersonalLightComponent
	var water_surface := actor.get_node_or_null("WaterSurface") as Sprite2D
	if visual == null or name_label == null or glow == null or water_surface == null:
		push_error("Player scene is missing an authored presentation child")
		return null
	visual.setup(HERO_PALETTE, ActorVisual.Kind.HUMAN, "player", "Human", "wind")
	name_label.text = str(GameState.profile_domain.profile.get("name", "Wanderer"))
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_label.add_theme_font_size_override("font_size", 11)
	name_label.add_theme_color_override("font_color", Color(0.86, 0.95, 1.0, 0.9))
	name_label.add_theme_color_override("font_outline_color", Color(0.02, 0.03, 0.06, 0.9))
	name_label.add_theme_constant_override("outline_size", 4)
	name_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	glow.texture = ProceduralArt.soft_glow(Color(1.0, 0.86, 0.88, 0.55), 128)
	glow.color = Color(1.0, 0.9, 0.72)
	glow.energy = 0.55
	glow.texture_scale = 2.6
	water_surface.texture = ProceduralArt.white_pixel()
	water_surface.visible = false
	return visual

func update_water_visual(in_water: bool, depth: float = 1.0) -> void:
	if actor == null:
		return
	var visual := actor.get_node_or_null("ActorVisual") as ActorVisual
	if visual != null:
		var sprite := visual.get_node_or_null("FrameSprite") as Sprite2D
		if in_water and sprite != null and sprite.texture != null:
			if _wade_sprite != sprite or _wade_material == null or sprite.material != _wade_material:
				_dry_material = sprite.material
				_wade_sprite = sprite
				_wade_material = ShaderMaterial.new()
				_wade_material.shader = WADE_SHADER
				sprite.material = _wade_material
			var sink := sprite.get_rect().size.y * 0.46 * clampf(depth, 0.08, 1.0)
			_wade_material.set_shader_parameter("sink_pixels", sink)
			_wade_material.set_shader_parameter("waterline_strength", clampf(depth * 1.5, 0.15, 1.0))
		elif not in_water and is_instance_valid(_wade_sprite):
			if _wade_sprite.material == _wade_material:
				_wade_sprite.material = _dry_material
			_wade_sprite = null
			_wade_material = null
			_dry_material = null
	var surface := actor.get_node_or_null("WaterSurface") as Sprite2D
	if surface != null:
		surface.visible = in_water
		surface.position = Vector2.ZERO
		var ripples := surface.get_node_or_null("RippleGeometry") as Node2D
		if ripples != null and visual != null:
			var size_factor := clampf(visual.visual_scale, 0.7, 1.5)
			ripples.scale = Vector2(size_factor / 46.0, size_factor / 5.0)
			ripples.modulate.a = clampf(depth * 1.6, 0.25, 1.0) if in_water else 0.0
		if not in_water:
			var burst := surface.get_node_or_null("RippleGeometry/SplashWake/AnimationPlayer") as AnimationPlayer
			if burst != null:
				burst.stop()
		var ripple_player := surface.get_node_or_null("AnimationPlayer") as AnimationPlayer
		if ripple_player != null and ripple_player.has_animation(&"ripple"):
			if in_water:
				if ripple_player.current_animation != &"ripple" or not ripple_player.is_playing():
					ripple_player.play(&"ripple")
			else:
				ripple_player.stop()
				surface.scale = Vector2(46.0, 5.0)
				surface.modulate = Color(0.35, 0.68, 0.86, 0.58)


func play_water_splash(entry: bool = false) -> void:
	if actor == null:
		return
	var burst := actor.get_node_or_null("WaterSurface/RippleGeometry/SplashWake/AnimationPlayer") as AnimationPlayer
	if burst != null:
		burst.stop()
		burst.play(&"entry" if entry else &"step")


func restore_facing(facing: Vector2) -> Vector2:
	if facing.length_squared() < 0.0001:
		facing = Vector2(0.0, 1.0)
	facing = facing.normalized()
	var visual := actor.get_node_or_null("ActorVisual") as ActorVisual if actor != null else null
	if visual != null:
		if absf(facing.x) > 0.1:
			visual.facing = 1.0 if facing.x > 0.0 else -1.0
		visual.set_move_direction(facing)
		visual.play(0)
	GameState.session_domain.set_player_facing(facing)
	return facing


func play_damage() -> void:
	_play_visual_cue("hit")


func play_victory() -> void:
	_play_visual_cue("play_victory")


func play_defeat() -> void:
	_play_visual_cue("play_defeat")


func play_attack() -> void:
	_play_visual_cue("play_attack")


func play_cast() -> void:
	_play_visual_cue("play_cast")


func _play_visual_cue(method_name: String) -> void:
	if actor == null:
		return
	var visual := actor.get_node_or_null("ActorVisual") as ActorVisual
	if visual != null and visual.has_method(method_name):
		visual.call(method_name)


func _on_battle_finished(result: Dictionary) -> void:
	if bool(result.get("victory", false)):
		play_victory()
	else:
		play_defeat()


func _on_encounter_requested(_group_id: String, _source: Node) -> void:
	play_attack()
