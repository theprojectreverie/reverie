class_name CombatFeedbackComponent
extends Node
## Owns transient combat feedback: floating numbers, banners, battle log and shake.

var screen: Control
var battlefield: Battlefield
var log_label: RichTextLabel
var boss_bar: Control
var log_lines: Array[String] = []
var _shake_timer: float = 0.0
var _shake_intensity: float = 0.0


func bind(owner_screen: Control, field: Battlefield, battle_log: RichTextLabel, boss_panel: Control) -> void:
	screen = owner_screen
	battlefield = field
	log_label = battle_log
	boss_bar = boss_panel
	_shake_timer = 0.0
	_shake_intensity = 0.0
	clear_log()


func clear_log() -> void:
	log_lines.clear()
	if log_label != null:
		log_label.text = ""


func float_text(actor: BattlefieldActor, text: String, color: Color, delay: float = 0.16) -> void:
	if battlefield == null or actor == null:
		return
	battlefield.spawn_damage_number(actor, text, color, delay)


func show_banner(text: String) -> void:
	if screen == null or not screen.is_inside_tree():
		return
	if text == "Eclipse Verdict":
		_show_eclipse_banner()
		return
	var banner := preload("res://scenes/ui/combat/components/battle_event_banner.tscn").instantiate() as PanelContainer
	if banner == null:
		return
	var title := banner.get_node_or_null("Title") as Label
	if title == null:
		banner.queue_free()
		return
	title.text = text
	title.add_theme_font_size_override("font_size", 24)
	title.add_theme_color_override("font_color", UITheme.GOLD_BRIGHT)
	title.add_theme_color_override("font_outline_color", Color(0.01, 0.02, 0.05, 0.95))
	title.add_theme_constant_override("outline_size", 5)
	title.add_theme_color_override("font_shadow_color", Color(0.0, 0.0, 0.0, 0.85))
	title.add_theme_constant_override("shadow_offset_x", 1)
	title.add_theme_constant_override("shadow_offset_y", 2)

	var frame_texture := load("res://assets/ui/battle/panels/battle_dialogue_panel.png") as Texture2D
	if frame_texture != null:
		var frame := StyleBoxTexture.new()
		frame.texture = frame_texture
		frame.texture_margin_left = 34.0
		frame.texture_margin_right = 34.0
		frame.texture_margin_top = 38.0
		frame.texture_margin_bottom = 38.0
		frame.content_margin_left = 58.0
		frame.content_margin_right = 58.0
		frame.content_margin_top = 38.0
		frame.content_margin_bottom = 38.0
		banner.add_theme_stylebox_override("panel", frame)
	else:
		push_warning("Battle dialogue frame could not be loaded; event banner uses the scene fallback.")

	if text.to_lower().contains("defeat"):
		title.add_theme_color_override("font_color", UITheme.DANGER)
	elif text.to_lower().contains("victory"):
		title.add_theme_color_override("font_color", UITheme.GOLD_BRIGHT)
	screen.add_child(banner)
	banner.modulate = Color(1, 1, 1, 0)
	var tween := screen.create_tween()
	tween.tween_property(banner, "modulate:a", 1.0, 0.22)
	tween.tween_interval(1.35)
	tween.tween_property(banner, "modulate:a", 0.0, 0.36)
	tween.tween_callback(banner.queue_free)



func show_boss_intro(boss_name: String) -> void:
	if screen == null or not screen.is_inside_tree():
		return
	var banner := preload("res://scenes/ui/combat/components/boss_intro_banner.tscn").instantiate() as PanelContainer
	if banner == null:
		return
	var eyebrow := banner.get_node_or_null("Content/TextStack/Eyebrow") as Label
	var title := banner.get_node_or_null("Content/TextStack/BossName") as Label
	var subline := banner.get_node_or_null("Content/TextStack/Subline") as Label
	if eyebrow == null or title == null or subline == null:
		banner.queue_free()
		push_error("Boss intro banner is missing an authored text node.")
		return
	title.text = boss_name
	eyebrow.add_theme_font_size_override("font_size", 11)
	eyebrow.add_theme_color_override("font_color", Color("#e5b8c8"))
	title.add_theme_font_size_override("font_size", 27)
	title.add_theme_color_override("font_color", UITheme.GOLD_BRIGHT)
	title.add_theme_color_override("font_outline_color", Color(0.01, 0.01, 0.03, 0.95))
	title.add_theme_constant_override("outline_size", 4)
	subline.add_theme_font_size_override("font_size", 11)
	subline.add_theme_color_override("font_color", UITheme.TEXT_DIM)
	var frame_texture := load("res://assets/ui/battle/panels/battle_dialogue_panel.png") as Texture2D
	if frame_texture != null:
		var frame := StyleBoxTexture.new()
		frame.texture = frame_texture
		frame.texture_margin_left = 34.0
		frame.texture_margin_right = 34.0
		frame.texture_margin_top = 38.0
		frame.texture_margin_bottom = 38.0
		frame.content_margin_left = 48.0
		frame.content_margin_right = 48.0
		frame.content_margin_top = 20.0
		frame.content_margin_bottom = 20.0
		banner.add_theme_stylebox_override("panel", frame)
	screen.add_child(banner)
	banner.modulate = Color(1.0, 1.0, 1.0, 0.0)
	banner.scale = Vector2(0.96, 0.96)
	var tween := screen.create_tween()
	tween.set_parallel(true)
	tween.set_trans(Tween.TRANS_CUBIC)
	tween.set_ease(Tween.EASE_OUT)
	tween.tween_property(banner, "modulate:a", 1.0, 0.28)
	tween.tween_property(banner, "scale", Vector2.ONE, 0.32)
	tween.set_parallel(false)
	tween.tween_interval(1.55)
	tween.tween_property(banner, "modulate:a", 0.0, 0.34)
	tween.tween_callback(banner.queue_free)


func log(line: String) -> void:
	log_lines.append(line)
	while log_lines.size() > 9:
		log_lines.pop_front()
	if log_label != null:
		log_label.text = "\n".join(log_lines)


func camera_shake(intensity: float, duration: float) -> void:
	_shake_intensity = maxf(_shake_intensity, intensity)
	_shake_timer = maxf(_shake_timer, duration)


func _process(delta: float) -> void:
	if _shake_timer <= 0.0:
		return
	_shake_timer -= delta
	var offset := Vector2(randf_range(-_shake_intensity, _shake_intensity), randf_range(-_shake_intensity, _shake_intensity))
	# Containers own HUD positions. Shake only the actor stage.
	if is_instance_valid(battlefield) and is_instance_valid(battlefield._stage):
		var quake := battlefield._gerald_quake_tween
		if quake == null or not quake.is_valid() or not quake.is_running():
			battlefield._stage.position = offset if _shake_timer > 0.0 else Vector2.ZERO
	if _shake_timer <= 0.0:
		_shake_intensity = 0.0


func _show_eclipse_banner() -> void:
	var banner := preload("res://scenes/ui/combat/components/eclipse_verdict_banner.tscn").instantiate() as PanelContainer
	screen.add_child(banner)
	banner.modulate.a = 0.0
	var motion := banner.create_tween()
	motion.tween_property(banner, "modulate:a", 1.0, 0.15)
	motion.tween_interval(0.58)
	motion.tween_property(banner, "modulate:a", 0.0, 0.2)
	motion.tween_callback(banner.queue_free)