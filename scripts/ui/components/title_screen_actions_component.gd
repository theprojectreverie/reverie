class_name TitleScreenActionsComponent
extends Node
## Owns title-page input, button states and title-only dialogs.

signal menu_requested(action: String)
signal quit_requested

const BUTTON_ACTIONS := {
	"ContinueButton": "continue", "NewJourneyButton": "new", "LoadGameButton": "load",
	"SettingsButton": "settings", "ExtrasButton": "extras", "QuitGameButton": "quit",
	"OnlineButton": "online"
}
var screen: Control

func bind(owner: Control) -> void:
	screen = owner
	for button_name in BUTTON_ACTIONS:
		var button := screen.get_node_or_null(button_name) as Button
		if button == null:
			push_error("[TitleActions] Missing authored hit target: %s" % button_name)
			continue
		var action: String = BUTTON_ACTIONS[button_name]
		button.tooltip_text = action.capitalize()
		button.pressed.connect(_on_action.bind(action))
		button.focus_mode = Control.FOCUS_ALL
		button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		button.add_theme_stylebox_override("normal", _transparent_style())
		button.add_theme_stylebox_override("hover", _hover_style())
		button.add_theme_stylebox_override("pressed", _pressed_style())
		button.add_theme_stylebox_override("focus", _hover_style())
		if button_name != "OnlineButton":
			button.text = ""
		else:
			button.add_theme_stylebox_override("normal", _online_style())
			button.add_theme_color_override("font_color", Color(0.96, 0.86, 0.75, 1.0))
			button.add_theme_font_size_override("font_size", 16)
	AuthGateway.authentication_changed.connect(func(_ok: bool, _player: Dictionary) -> void: refresh_save_actions())
	AuthGateway.session_restore_finished.connect(refresh_save_actions)
	refresh_save_actions()

func refresh_save_actions() -> void:
	if screen == null:
		return
	var has_save := SaveService.has_save() if AuthGateway.is_authenticated() else true
	var continue_button := screen.get_node_or_null("ContinueButton") as Button
	var load_button := screen.get_node_or_null("LoadGameButton") as Button
	if continue_button != null:
		continue_button.disabled = not has_save
	if load_button != null:
		load_button.disabled = not has_save

func _on_action(action: String) -> void:
	match action:
		"continue", "new", "load":
			menu_requested.emit(action)
		"online":
			_open_account()
		"settings":
			_open_settings()
		"extras":
			_show_extras()
		"quit":
			quit_requested.emit()

func _open_account() -> void:
	if screen.has_node("AccountOverlay"):
		return
	var packed := load("res://scenes/online/account_screen.tscn") as PackedScene
	if packed == null:
		EventBus.toast_requested.emit("Online account services are unavailable.")
		return
	var overlay := packed.instantiate() as Control
	overlay.name = "AccountOverlay"
	overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	overlay.z_index = 30
	screen.add_child(overlay)
	overlay.connect("closed", Callable(overlay, "queue_free"))
	overlay.connect("account_authenticated", Callable(self, "_on_online_account_authenticated").bind(overlay))

func _on_online_account_authenticated(player: Dictionary, overlay: Control) -> void:
	EventBus.toast_requested.emit("Signed in as %s." % str(player.get("name", "Wanderer")))
	if is_instance_valid(overlay):
		overlay.queue_free()
	_open_coop_lobby()

func _open_coop_lobby() -> void:
	if screen.has_node("CoopLobbyOverlay"):
		return
	var packed := load("res://scenes/online/coop_lobby_screen.tscn") as PackedScene
	if packed == null:
		EventBus.toast_requested.emit("Co-op expedition services are unavailable.")
		return
	var lobby := packed.instantiate() as Control
	lobby.name = "CoopLobbyOverlay"
	lobby.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	lobby.z_index = 31
	screen.add_child(lobby)
	lobby.connect("closed", Callable(lobby, "queue_free"))

func _online_style() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.055, 0.035, 0.075, 0.88)
	style.border_color = Color(0.79, 0.66, 0.53, 0.9)
	style.set_border_width_all(1)
	style.set_corner_radius_all(12)
	style.content_margin_left = 14
	style.content_margin_right = 14
	return style

func _open_settings() -> void:
	if screen.has_node("TitleSettingsOverlay"):
		return
	var packed := load("res://scenes/ui/settings_screen.tscn") as PackedScene
	if packed == null:
		EventBus.toast_requested.emit("Settings are currently unavailable.")
		return
	var overlay := packed.instantiate() as Control
	overlay.name = "TitleSettingsOverlay"
	overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	overlay.z_index = 20
	screen.add_child(overlay)
	if overlay.has_signal("closed"):
		overlay.closed.connect(func() -> void:
			if is_instance_valid(overlay):
				overlay.queue_free()
		)

func _show_extras() -> void:
	var dialog := AcceptDialog.new()
	dialog.title = "Reverie — Extras"
	dialog.dialog_text = "A story of two souls.\n\nCreated with love for dark fantasy, forgotten memories, and the bond between Gerald and Lilith.\n\nReplay the opening dream without changing your progress."
	dialog.add_button("Replay Kael's dream", true, "replay_dream")
	screen.add_child(dialog)
	dialog.custom_action.connect(func(action: StringName) -> void:
		if action == &"replay_dream":
			dialog.hide()
			dialog.queue_free()
			_replay_opening()
	)
	dialog.confirmed.connect(dialog.queue_free)
	dialog.canceled.connect(dialog.queue_free)
	dialog.popup_centered()

func _replay_opening() -> void:
	if not is_instance_valid(screen) or not screen.is_inside_tree():
		return
	var host := screen.get_parent()
	if host.has_node("OpeningCinematicReplay"):
		return
	var packed: PackedScene = preload("res://scenes/ui/opening_cinematic.tscn")
	var cinematic := packed.instantiate()
	cinematic.name = "OpeningCinematicReplay"
	screen.hide()
	cinematic.finished.connect(func() -> void:
		if is_instance_valid(cinematic):
			cinematic.queue_free()
		if is_instance_valid(screen):
			screen.show()
			AudioDirector.play_title_theme()
	, CONNECT_ONE_SHOT)
	host.add_child(cinematic)

func _transparent_style() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0, 0, 0, 0)
	style.border_color = Color(0, 0, 0, 0)
	return style

func _hover_style() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.48, 0.19, 0.38, 0.16)
	style.border_color = Color(0.91, 0.77, 0.66, 0.55)
	style.set_border_width_all(1)
	style.set_corner_radius_all(14)
	return style

func _pressed_style() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.36, 0.10, 0.25, 0.24)
	style.border_color = Color(0.93, 0.79, 0.59, 0.8)
	style.set_border_width_all(2)
	style.set_corner_radius_all(14)
	return style
