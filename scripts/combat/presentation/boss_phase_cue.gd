extends Control
## Boss-specific phase transition. Boss presentation changes only; combat rules stay deterministic.

signal finished

@onready var _veil: ColorRect = $Veil
@onready var _panel: PanelContainer = $PhasePanel
@onready var _boss_line: Label = $PhasePanel/Content/TextStack/BossLine
@onready var _title: Label = $PhasePanel/Content/TextStack/PhaseTitle
@onready var _message: Label = $PhasePanel/Content/TextStack/PhaseMessage
@onready var _root_mark: TextureRect = $PhasePanel/Content/RootCrest
@onready var _matron_mark: TextureRect = $PhasePanel/Content/MatronCrest
@onready var _animation_player: AnimationPlayer = $AnimationPlayer


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_animation_player.animation_finished.connect(_on_animation_finished)
	visible = false


func play_cue(message: String, phase_title: String, boss_name: String,
		phase_number: int, phase_label: String, accent_color: Color,
		visual_style: String, duration: float = 1.55) -> void:
	var is_bloom := visual_style == "bloom"
	var is_eclipse := visual_style == "eclipse"
	var small_landscape := is_eclipse and get_window().size.x < 1000 and get_window().size.x > get_window().size.y
	_boss_line.add_theme_font_size_override("font_size", 19 if small_landscape else 11)
	_title.add_theme_font_size_override("font_size", 36 if small_landscape else 29)
	_message.add_theme_font_size_override("font_size", 24 if small_landscape else 14)
	$PhasePanel/Content/RaviennaCrest.visible = is_eclipse
	_root_mark.visible = not is_bloom and not is_eclipse
	_matron_mark.visible = is_bloom
	_root_mark.modulate = accent_color.lerp(Color.WHITE, 0.28)
	_matron_mark.modulate = accent_color.lerp(Color.WHITE, 0.22)

	_boss_line.text = "%s  •  PHASE %d — %s" % [
		boss_name.to_upper() if not boss_name.strip_edges().is_empty() else "BOSS",
		phase_number,
		phase_label.to_upper(),
	]
	_title.text = phase_title.to_upper()
	_message.text = message
	_boss_line.add_theme_color_override("font_color", accent_color)
	_title.add_theme_color_override("font_color", accent_color.lerp(Color.WHITE, 0.2))
	_title.add_theme_color_override("font_outline_color", Color(0.025, 0.018, 0.035, 0.96))
	_title.add_theme_constant_override("outline_size", 5)
	_message.add_theme_color_override("font_color", Color("#e1eadc") if not is_bloom and not is_eclipse else Color("#f1deef"))

	_veil.color = Color("#160b25") if is_eclipse else (Color("#06150d") if not is_bloom else Color("#18091d"))
	_veil.modulate.a = 0.0
	_panel.modulate = Color(1.0, 1.0, 1.0, 0.0)
	_panel.scale = Vector2(0.965, 0.965)

	# The dialogue frame is authored on PhasePanel in the scene; runtime
	# code only supplies encounter-specific text, colors, and animation timing.
	visible = true
	var animation := _animation_player.get_animation("phase_change")
	_animation_player.speed_scale = animation.length / maxf(0.2, duration)
	_animation_player.play("phase_change")


func cancel_cue() -> void:
	var was_visible := visible
	_animation_player.stop()
	_animation_player.clear_caches()
	visible = false
	if was_visible:
		finished.emit()


func _on_animation_finished(animation_name: StringName) -> void:
	if animation_name != &"phase_change":
		return
	visible = false
	finished.emit()


func _exit_tree() -> void:
	if is_instance_valid(_animation_player):
		_animation_player.stop()
		_animation_player.clear_caches()
