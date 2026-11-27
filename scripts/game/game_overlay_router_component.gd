class_name GameOverlayRouterComponent
extends Node
## Owns creation and lifecycle of modal screens. Gameplay remains suspended by the session owner.

signal overlay_closed
signal main_menu_requested
signal reset_requested
signal navigate_requested(screen_id: String)

@export var overlay_root_path: NodePath = NodePath("../UI/Overlays")

const SCREEN_SCENES := {
	"gacha": "res://scenes/ui/gacha_screen.tscn",
	"collection": "res://scenes/ui/collection_screen.tscn",
	"inventory": "res://scenes/ui/inventory_screen.tscn",
	"quests": "res://scenes/ui/quest_screen.tscn",
	"chat": "res://scenes/ui/chat_screen.tscn",
	"social": "res://scenes/ui/social_screen.tscn",
	"shop": "res://scenes/ui/shop_screen.tscn",
}
const PAUSE_MENU_PATH := "res://scenes/ui/pause_menu.tscn"

var overlay_root: Control
var active_overlay: OverlayScreen
var _suspended_hud: Control
var _hud_was_visible := false


func _ready() -> void:
	overlay_root = get_node_or_null(overlay_root_path) as Control


func open_screen(screen_id: String) -> bool:
	if active_overlay != null and is_instance_valid(active_overlay):
		return false
	var scene: PackedScene
	var path := str(SCREEN_SCENES.get(screen_id, ""))
	if not path.is_empty():
		scene = load(path) as PackedScene
	if screen_id == "map":
		scene = load("res://scenes/ui/map_screen.tscn") as PackedScene
		if scene != null and not scene.can_instantiate():
			scene = ResourceLoader.load("res://scenes/ui/map_screen.tscn", "PackedScene", ResourceLoader.CACHE_MODE_IGNORE) as PackedScene
	if scene == null and screen_id == "settings" and ResourceLoader.exists("res://scenes/ui/settings_screen.tscn"):
		scene = load("res://scenes/ui/settings_screen.tscn") as PackedScene
	if scene == null or not scene.can_instantiate():
		push_warning("[GameOverlayRouter] Unknown or unavailable screen: " + screen_id)
		return false
	var screen := scene.instantiate() as OverlayScreen
	if screen == null:
		push_error("[GameOverlayRouter] Screen scene is not an OverlayScreen: " + screen_id)
		return false
	return _attach_overlay(screen, "Overlay_" + screen_id)


func open_pause_menu() -> bool:
	if active_overlay != null and is_instance_valid(active_overlay):
		return false
	var packed := load(PAUSE_MENU_PATH) as PackedScene
	if packed == null or not packed.can_instantiate():
		return false
	var menu := packed.instantiate() as PauseMenu
	if menu == null:
		return false
	menu.main_menu_requested.connect(_on_pause_main_menu_requested)
	menu.reset_requested.connect(_on_pause_reset_requested)
	menu.navigate_requested.connect(_on_pause_navigate_requested)
	return _attach_overlay(menu, "PauseMenu")


func _attach_overlay(screen: OverlayScreen, node_name: String) -> bool:
	if overlay_root == null:
		overlay_root = get_node_or_null(overlay_root_path) as Control
	if overlay_root == null:
		push_error("[GameOverlayRouter] Overlay root is missing.")
		screen.free()
		return false
	active_overlay = screen
	screen.name = node_name
	screen.closed.connect(_on_overlay_closed)
	if screen.has_signal("private_chat_requested"):
		screen.connect("private_chat_requested",_open_private_chat)
	_suspend_world_hud()
	overlay_root.add_child(screen)
	return true


func _open_private_chat(player_id: String) -> void:
	if not is_instance_valid(active_overlay):return
	var previous:=active_overlay
	var packed := load(SCREEN_SCENES["chat"]) as PackedScene
	if packed == null or not packed.can_instantiate():return
	var chat:=packed.instantiate() as OverlayScreen
	if chat==null:return
	chat.call("set_initial_recipient",player_id)
	previous.closed.disconnect(_on_overlay_closed)
	active_overlay=null
	if _attach_overlay(chat,"Overlay_chat"):
		previous.close_screen()
	else:
		active_overlay=previous
		previous.closed.connect(_on_overlay_closed)

func _suspend_world_hud() -> void:
	# Keep the original visibility through modal-to-modal navigation.
	if is_instance_valid(_suspended_hud):
		return
	var candidate := overlay_root.get_parent().get_node_or_null("HUD") as Control
	if candidate == null:
		return
	_suspended_hud = candidate
	_hud_was_visible = candidate.visible
	candidate.hide()
	TouchInput.release()


func _restore_world_hud() -> void:
	if is_instance_valid(_suspended_hud):
		_suspended_hud.visible = _hud_was_visible
	_suspended_hud = null


func _on_overlay_closed() -> void:
	active_overlay = null
	_restore_world_hud()
	overlay_closed.emit()


func close_active() -> void:
	if active_overlay != null and is_instance_valid(active_overlay):
		active_overlay.close_screen()



func _on_pause_main_menu_requested() -> void:
	main_menu_requested.emit()


func _on_pause_reset_requested() -> void:
	reset_requested.emit()


func _on_pause_navigate_requested(screen_id: String) -> void:
	if active_overlay != null and is_instance_valid(active_overlay):
		active_overlay.close_screen()
	navigate_requested.emit(screen_id)
