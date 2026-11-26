extends Node

# Signal adapter for the existing authored HUD and overlay scenes.
const CHECKPOINT = preload("res://scripts/world/six_zone_reverie/six_zone_checkpoint.gd")
@onready var zone: Node2D = get_parent()
@onready var hud: HUD = zone.get_node("UI/HUD")
@onready var router: GameOverlayRouterComponent = zone.get_node("OverlayRouter")

func _ready() -> void:
    if zone.has_node("CombatRouter"):
        EventBus.encounter_requested.connect(_encounter)
        zone.get_node("CombatRouter").combat_closed.connect(_resume)
    var beacon := preload("res://scenes/world/quest_destination_marker.tscn").instantiate() as Node2D
    beacon.name = "ChapterQuestBeacon"
    beacon.visible = false
    zone.add_child.call_deferred(beacon)
    hud.screen_requested.connect(_open_screen)
    hud.menu_requested.connect(_open_pause)
    hud.return_to_title_requested.connect(_return_to_title)
    hud.interact_requested.connect(_interact)
    hud.switch_avatar_requested.connect(_switch_avatar)
    router.main_menu_requested.connect(_return_to_title)
    router.overlay_closed.connect(_resume)
    router.navigate_requested.connect(_navigate)
    var names := ["Royal Gardens", "Royal Gate", "Willow Fields", "Elderwood Grove", "Forsaken Ruins", "Ruined Tower"]
    var index := int(str(zone.name).right(2)) - 1
    if zone.name == "StandaloneVillage":
        hud.set_world_info("Village", "Exploration")
    elif index >= 0 and index < names.size():
        hud.set_world_info(names[index], "Exploration")
    # Royal Gardens already owns the top-center interaction instruction.
    if zone.has_node("NPCDialogueLayer/InteractionPrompt"):
        hud.get_node("Prompt").set_process(false)

func _player() -> CharacterBody2D:
    return zone.get("checkpoint_player") as CharacterBody2D

func _dialogue_busy() -> bool:
    var dialogue := zone.get_node_or_null("NPCDialogueLayer/Dialogue") as Control
    if dialogue == null:
        dialogue = zone.get_node_or_null("UI/Dialogue") as Control
    return dialogue != null and dialogue.visible

func _open_pause() -> void:
    if _travel_or_combat_busy():
        return
    if not _dialogue_busy() and router.open_pause_menu():
        _suspend()
        # Do not expose the legacy reset action in this checkpoint-based world.
        var reset := router.active_overlay.get_node_or_null("OverlayShell/Margin/Panel/Root/Content")
        if reset != null:
            var button := reset.find_child("ResetButton", true, false) as Button
            if button != null:
                button.hide()

func _open_screen(id: String) -> void:
    if _travel_or_combat_busy():
        return
    if not _dialogue_busy() and router.open_screen(id):
        _suspend()

func _navigate(id: String) -> void:
    call_deferred("_open_screen", id)

func _suspend() -> void:
    var player := _player()
    if is_instance_valid(player):
        player.set("input_enabled", false)
        player.velocity = Vector2.ZERO
    TouchInput.release()

func _resume() -> void:
    if _travel_or_combat_busy():
        return
    var player := _player()
    if is_instance_valid(player) and not _dialogue_busy():
        player.set("input_enabled", true)

func _interact() -> void:
    var player := _player()
    if is_instance_valid(player) and bool(player.get("input_enabled")) and router.active_overlay == null:
        player.call("try_interact")

func _switch_avatar() -> void:
    var player := _player()
    if is_instance_valid(player) and bool(player.get("input_enabled")) and router.active_overlay == null:
        player.call("cycle_avatar")

func _return_to_title() -> void:
    if bool(zone.get_meta("portal_load_pending", false)):
        return
    if bool(zone.get_meta("gerald_backstory_active", false)) or bool(zone.get_meta("cassien_ritual_active", false)) or bool(zone.get_meta("ravienna_ending_active", false)):
        return
    CHECKPOINT.capture(zone, _player(), true)
    GameState.save_now()
    TouchInput.release()
    get_tree().change_scene_to_file("res://scenes/main.tscn")

func _unhandled_input(event: InputEvent) -> void:
    if router.active_overlay != null or _dialogue_busy() or event.is_echo():
        return
    if zone.has_node("CombatRouter") and zone.get_node("CombatRouter").active_combat != null:
        return
    if event.is_action_pressed("interact"):
        var player := _player()
        if is_instance_valid(player) and player.input_enabled:
            player.get_node("InteractionComponent").refresh_nearest()
            _interact()
            get_viewport().set_input_as_handled()
        return
    if event.is_action_pressed("open_menu") or event.is_action_pressed("ui_cancel"):
        _open_pause()
        get_viewport().set_input_as_handled()

func _travel_or_combat_busy() -> bool:
    if bool(zone.get_meta("portal_load_pending", false)):
        return true
    if bool(zone.get_meta("gerald_backstory_active", false)) or bool(zone.get_meta("cassien_ritual_active", false)) or bool(zone.get_meta("ravienna_ending_active", false)):
        return true
    if bool(zone.get_meta("coop_boss_panel_open", false)):
        return true
    if bool(zone.get_meta("fast_travel_pending", false)) or bool(zone.get_meta("fast_travel_visual_pending", false)):
        return true
    var combat := zone.get_node_or_null("CombatRouter") as GameCombatRouterComponent
    return combat != null and combat.active_combat != null

func _encounter(group_id: String, source: Node) -> void:
    var combat := zone.get_node("CombatRouter") as GameCombatRouterComponent
    if _travel_or_combat_busy() or _dialogue_busy() or router.active_overlay != null or not combat.start_encounter(group_id):
        if is_instance_valid(source):
            source.set("engaged", false)
        return
    _suspend()