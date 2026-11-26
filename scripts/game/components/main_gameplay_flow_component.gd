class_name MainGameplayFlowComponent
extends Node
## Owns the Main Menu -> Opening Cinematic -> Loading -> Gameplay transition.
signal quit_requested
const CHECKPOINT = preload("res://scripts/world/six_zone_reverie/six_zone_checkpoint.gd")
const INTRO_SCENE: PackedScene = preload("res://scenes/ui/opening_cinematic.tscn")
const LOADING_SCENE: PackedScene = preload("res://scenes/ui/loading_screen.tscn")
var host: Control
var menu: MainMenu
var loading: LoadingScreen
var intro: Node
var _account_start_pending := false

func bind(owner: Control, startup: MainStartupFlowComponent) -> void:
	host = owner
	startup.main_menu_ready.connect(_on_menu_ready)
	startup.new_journey_requested.connect(_start_new_journey)

func _start_new_journey() -> void:
	if not await AuthGateway.refresh_account_roster():
		# Return to account-required title rather than starting with an empty party.
		get_tree().change_scene_to_file("res://scenes/main.tscn")
		return
	if menu != null and is_instance_valid(menu):
		menu.queue_free()
		menu = null
	if host.has_node("OpeningCinematic") or loading != null:
		return
	# The tutorial is a standalone scene, not a streamed world region. Keep the
	# destination region valid in save data while the prologue scene is active.
	GameState.session_domain.set_player_region("castle_royal_gardens")
	GameState.session_domain.set_active_world("castle_royal_gardens")
	_show_story_intro()

func _on_menu_ready(ready_menu: MainMenu) -> void:
	menu = ready_menu
	menu.play_requested.connect(_start_game)
	menu.quit_requested.connect(quit_requested.emit)

func _start_game() -> void:
	if _account_start_pending:
		return
	if not AuthGateway.is_authenticated():
		if is_instance_valid(menu):
			menu._open_profile_account()
		return
	_account_start_pending = true
	var ready := await AuthGateway.refresh_account_roster()
	_account_start_pending = false
	if not ready or not AuthGateway.is_authenticated():
		EventBus.toast_requested.emit("Account connection unavailable. Reconnect before playing.")
		return
	# A completed tutorial resumes the saved world without rewriting its region
	# while the destination is still loading.
	if bool(GameState.quest_domain.flags.get("tutorial_complete", false)):
		_load_gameplay()
		return
	GameState.session_domain.set_player_region("castle_royal_gardens")
	GameState.session_domain.set_active_world("castle_royal_gardens")
	if not needs_opening_cinematic(GameState.quest_domain.flags):
		_load_tutorial()
		return
	_show_story_intro()

static func needs_opening_cinematic(flags: Dictionary) -> bool:
	# A save may have been created by account login before the dream played.
	# Never replay automatically after the tutorial is complete.
	return not bool(flags.get("tutorial_complete",false)) and not bool(flags.get("kael_opening_seen",false))

func _show_story_intro() -> void:
	if host.has_node("OpeningCinematic") or loading != null:
		return
	if menu != null and is_instance_valid(menu):
		menu.visible = false
		menu.set_process_unhandled_input(false)
	intro = INTRO_SCENE.instantiate()
	intro.name = "OpeningCinematic"
	var intro_owner := str(AuthGateway.current_player().get("id",""))
	intro.finished.connect(func() -> void:
		if not AuthGateway.is_authenticated() or str(AuthGateway.current_player().get("id","")) != intro_owner:
			get_tree().change_scene_to_file("res://scenes/main.tscn")
			return
		GameState.quest_domain.flags["kael_opening_seen"] = true
		GameState.save_now()
		if menu != null and is_instance_valid(menu):
			menu.queue_free()
			menu = null
		if is_instance_valid(intro):
			intro.queue_free()
		intro = null
		_load_tutorial()
	)
	host.add_child(intro)

func _load_tutorial() -> void:
	var error := get_tree().change_scene_to_file("res://scenes/world/tutorial_prologue/kael_diamond_bedroom.tscn")
	if error != OK:
		push_error("[GameplayFlow] Kael bedroom scene failed to load (error %d)." % error)
		_load_gameplay()

func _load_gameplay() -> void:
	if loading != null and is_instance_valid(loading):
		return
	loading = LOADING_SCENE.instantiate() as LoadingScreen
	if loading == null:
		push_error("[GameplayFlow] Loading screen failed to instantiate.")
		return
	loading.name = "GameplayLoadingScreen"
	loading.target_scene_path = CHECKPOINT.resume_scene()
	loading.scene_loaded.connect(_on_game_loaded)
	loading.load_failed.connect(_on_game_load_failed)
	host.add_child(loading)

func _on_game_loaded(packed: PackedScene) -> void:
	var error := get_tree().change_scene_to_packed(packed)
	if error != OK:
		push_error("[GameplayFlow] Scene switch failed (error %d)." % error)
		_on_game_load_failed()

func _on_game_load_failed() -> void:
	push_error("[GameplayFlow] Threaded gameplay load failed; retrying direct scene load.")
	var error := get_tree().change_scene_to_file(CHECKPOINT.resume_scene())
	if error != OK:
		EventBus.toast_requested.emit("Could not start the journey.")
