class_name RemotePlayerAvatar
extends Node2D
## Lightweight presentation-only remote avatar. It has no collision or camera.

const ACTOR_SCENE: PackedScene = preload("res://scenes/characters/actor_visual.tscn")
var player_id := ""
var display_name := "Wanderer"
var display_title := ""
var title_label: Label
var target_position := Vector2.ZERO
var visual: ActorVisual
var name_label: Label
var _last_direction := Vector2.DOWN
var expedition_kael := false
var attack_animation_count := 0
const PRESENTATION_CHECK_INTERVAL := 0.12
const SCREEN_MARGIN := 320.0
var _presentation_elapsed := PRESENTATION_CHECK_INTERVAL
var _presentation_culled := false

func _ready() -> void:
	visual = ACTOR_SCENE.instantiate() as ActorVisual
	visual.name = "ActorVisual"
	add_child(visual)
	# Until profiles expose a validated selected-character ID, keep remote
	# players neutral instead of depicting every connected player as Kael.
	if expedition_kael:
		var definition = ContentDB.get_character("kael")
		visual.setup(definition.palette, ActorVisual.Kind.HUMAN, "kael", definition.race, definition.element)
		var report := visual.configure_character("kael")
		if not bool(report.get("registered", false)):
			visual.hide()
	else:
		visual.setup({}, ActorVisual.Kind.HUMAN, "remote_player")
	name_label = Label.new()
	name_label.name = "NameLabel"
	name_label.text = display_name
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_label.position = Vector2(-64, -104)
	name_label.size = Vector2(128, 24)
	name_label.add_theme_font_size_override("font_size", 12)
	name_label.add_theme_color_override("font_color", Color("#f1e7d2"))
	name_label.add_theme_color_override("font_shadow_color", Color("#211a2b"))
	name_label.add_theme_constant_override("shadow_offset_x", 1)
	name_label.add_theme_constant_override("shadow_offset_y", 1)
	add_child(name_label)
	title_label = Label.new()
	title_label.name = "TitleLabel"
	title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title_label.position = Vector2(-110,-128)
	title_label.size = Vector2(220,24)
	title_label.add_theme_font_size_override("font_size", 11)
	title_label.add_theme_color_override("font_color", Color("#d4ad69"))
	title_label.add_theme_color_override("font_shadow_color", Color("#211a2b"))
	title_label.add_theme_constant_override("shadow_offset_x",1)
	title_label.add_theme_constant_override("shadow_offset_y",1)
	title_label.mouse_filter=Control.MOUSE_FILTER_IGNORE
	add_child(title_label)
	set_display_title(display_title)
	position = target_position
	GraphicsSettings.quality_changed.connect(_refresh_presentation_budget)
	_refresh_presentation_budget.call_deferred()

func configure(id: String, label: String, spawn_position: Vector2) -> void:
	player_id = id
	display_name = label if not label.is_empty() else "Wanderer"
	target_position = spawn_position
	position = spawn_position
	if name_label != null:
		name_label.text = display_name

func set_display_title(value:String) -> void:
	display_title=value
	if is_instance_valid(title_label):
		title_label.text=value
		title_label.add_theme_color_override("font_color",preload("res://scripts/ui/achievement_title_style.gd").color(value))
		title_label.visible=not value.is_empty()

func set_authoritative_position(next_position: Vector2) -> void:
	var delta := next_position - target_position
	if delta.length_squared() > 0.01:
		_last_direction = delta.normalized()
		target_position = next_position
		if visual != null and not _attack_playing():
			visual.set_move_direction(_last_direction)
			visual.walking = true
			visual.play(ActorVisual.S_WALK)
	else:
		target_position = next_position

func _process(delta: float) -> void:
	position = position.lerp(target_position, 1.0 - exp(-14.0 * delta))
	if visual != null and not _attack_playing() and position.distance_squared_to(target_position) < 3.0:
		if visual.walking or (visual.animator != null and visual.animator.state != ActorVisual.S_IDLE):
			visual.walking = false
			visual.play(ActorVisual.S_IDLE)
	_presentation_elapsed += delta
	if _presentation_elapsed >= PRESENTATION_CHECK_INTERVAL:
		_presentation_elapsed = 0.0
		_refresh_presentation_budget()


func _refresh_presentation_budget() -> void:
	if not is_inside_tree() or not is_instance_valid(visual):
		return
	# Use the actual canvas transform (camera position and zoom), with a
	# generous margin so an entering character never appears at a screen edge.
	# Do not overwrite ActorVisual.visible: an unavailable authored sprite may
	# intentionally be hidden independently of this budget.
	var near_screen := get_viewport_rect().grow(SCREEN_MARGIN).has_point(get_global_transform_with_canvas().origin)
	var culled := GraphicsSettings.quality < 2 and not near_screen
	if culled != _presentation_culled:
		_presentation_culled = culled
		visible = not culled
	var runtime := visual.animation_runtime_component
	if runtime != null:
		var interval := 0.0
		if culled:
			interval = 0.25 if GraphicsSettings.quality == 0 else 0.125
		elif not _attack_playing() and is_instance_valid(get_parent()):
			# Only remote animation cadence is reduced in a crowded region.
			# Movement interpolation, authored sprite visibility and local combat stay unchanged.
			var crowd_size := get_parent().get_child_count()
			if GraphicsSettings.quality == 0 and crowd_size >= 32:
				interval = 1.0 / 15.0
			elif GraphicsSettings.quality == 1 and crowd_size >= 64:
				interval = 1.0 / 30.0
		runtime.set_presentation_interval(interval)

func _attack_playing() -> bool:
	return visual != null and visual.animator != null and visual.animator.state == ActorVisual.S_ATTACK and not visual.animator.is_finished()

func play_confirmed_attack(monster_position: Vector2) -> void:
	if not expedition_kael or visual == null or visual.animator == null:
		return
	var direction := monster_position - target_position
	if direction.length_squared() > 0.01:
		_last_direction = direction.normalized()
	visual.walking = false
	visual.set_move_direction(_last_direction)
	visual.play(ActorVisual.S_ATTACK)
	if visual.animator.state == ActorVisual.S_ATTACK:
		attack_animation_count += 1