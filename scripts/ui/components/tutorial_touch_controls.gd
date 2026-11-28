extends CanvasLayer
## Reuses the authored world joystick and action button components in opening scenes.
@export var training_actions := false
@onready var controls: Control = $Controls
@onready var joystick: Control = $Controls/Joystick
@onready var interact: Button = $Controls/Actions/Interact
@onready var attack: Button = $Controls/Actions/Attack
@onready var skill: Button = $Controls/Actions/Skill
@onready var dodge: Button = $Controls/Actions/Dodge
var _player: Player

func _ready() -> void:
	_player = get_parent().get_node_or_null("Kael") as Player
	controls.theme = UITheme.build()
	interact.pressed.connect(_interact)
	attack.pressed.connect(_combat.bind("attack"))
	skill.pressed.connect(_combat.bind("skill"))
	dodge.pressed.connect(_combat.bind("dodge"))
	get_viewport().size_changed.connect(_layout)
	_layout()
	_refresh()

func _process(_delta: float) -> void:
	_refresh()

func _enabled() -> bool:
	return TouchInput.using_touch and is_instance_valid(_player) and _player.input_enabled and not _player.network_recovery_paused

func _refresh() -> void:
	var active := _enabled()
	if controls.visible and not active:
		TouchInput.release()
	controls.visible = active
	if not active:
		return
	interact.visible = training_actions and not _player.current_prompt().is_empty()
	var combat = _player.get_node_or_null("WorldCombatComponent")
	var practice: bool = training_actions and bool(get_parent().get("practice_ready")) and not bool(get_parent().get("dummy_complete")) and combat != null
	attack.visible = practice
	skill.visible = practice
	dodge.visible = practice
	if practice:
		attack.disabled = combat.cooldown > 0.0 or combat.attack_pending or combat.skill_pending or combat.dodge_time > 0.0
		skill.disabled = combat.skill_cooldown > 0.0 or combat.attack_pending or combat.skill_pending or combat.dodge_time > 0.0
		dodge.disabled = combat.dodge_recovery > 0.0 or combat.attack_pending or combat.skill_pending

func _interact() -> void:
	if _enabled() and training_actions:
		_player.interaction_component.refresh_nearest()
		_player.try_interact()

func _combat(action: String) -> void:
	if not _enabled() or not training_actions or not bool(get_parent().get("practice_ready")) or bool(get_parent().get("dummy_complete")):
		return
	var combat := _player.get_node_or_null("WorldCombatComponent")
	if combat != null:
		combat.call("try_" + action)

func _layout() -> void:
	var viewport := get_viewport().get_visible_rect().size
	var unit := clampf(minf(viewport.x, viewport.y) / 720.0, 0.85, 1.6)
	var margin := 24.0 * unit
	var left := margin
	var right := margin
	var bottom := margin
	if OS.has_feature("mobile"):
		var screen := DisplayServer.screen_get_size()
		var safe := DisplayServer.get_display_safe_area()
		if screen.x > 0 and screen.y > 0 and safe.size.x > 0 and safe.size.y > 0:
			var ratio := viewport / Vector2(screen)
			left += maxf(0.0, safe.position.x * ratio.x)
			right += maxf(0.0, (screen.x - safe.end.x) * ratio.x)
			bottom += maxf(0.0, (screen.y - safe.end.y) * ratio.y)
	joystick.scale = Vector2.ONE * unit
	joystick.pivot_offset = Vector2(0,170)
	joystick.offset_left = left
	joystick.offset_right = left + 170
	joystick.offset_top = -bottom - 170
	joystick.offset_bottom = -bottom
	var actions := $Controls/Actions as VBoxContainer
	actions.offset_left = -right - 140.0 * unit
	actions.offset_right = -right
	actions.offset_bottom = -bottom
	actions.offset_top = -bottom - 4.0 * 58.0 * unit - 24.0
	for button in actions.get_children():
		button.custom_minimum_size = Vector2(140,58) * unit
		button.add_theme_font_size_override("font_size", roundi(19.0 * unit))

func _exit_tree() -> void:
	TouchInput.release()