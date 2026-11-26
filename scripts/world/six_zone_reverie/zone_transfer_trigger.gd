extends Area2D

## Editor-authored transfer trigger; collision is a detection area, not a wall.
@export_file("*.tscn") var destination_scene: String
@export var arrival_marker: StringName = &"ToPreviousZone"
@export var required_story_flag: String = ""
@export var required_quest: String = ""
@export var previously_visited_zone: String = ""
@export var locked_route_text: String = ""
static var pending_arrival: StringName = &""
var transferring := false
var _loading_player: WeakRef
var _loading_scene: WeakRef

func _ready() -> void:
    monitoring = true
    collision_layer = 0
    collision_mask = 2
    body_entered.connect(_on_body_entered)
    # Only gated exits need an overlap recheck after a story unlock.
    set_physics_process(not _story_unlocked())
    _refresh_route_label()
    set_process(false)

func _physics_process(_delta: float) -> void:
    _refresh_route_label()
    if not _story_unlocked():
        return
    for body in get_overlapping_bodies():
        if body.is_in_group("player"):
            if _travel_blocked(body):
                return
            set_physics_process(false)
            _on_body_entered(body)
            return
    set_physics_process(false)

func _travel_blocked(body: Node2D) -> bool:
    if bool(body.get("network_recovery_paused")):
        return true
    if not bool(body.get("input_enabled")):
        return true
    var scene := get_tree().current_scene
    if scene == null:
        return true
    for key in ["fast_travel_pending", "fast_travel_visual_pending", "gerald_backstory_active", "cassien_ritual_active", "ravienna_ending_active", "portal_load_pending"]:
        if bool(scene.get_meta(key, false)):
            return true
    return false

func _on_body_entered(body: Node2D) -> void:
    if transferring or not body.is_in_group("player") or destination_scene.is_empty():
        return
    if not _story_unlocked() or _travel_blocked(body):
        # A body_entered signal is only emitted once per overlap. Recheck until
        # the player leaves, the story unlocks, or the current modal finishes.
        set_physics_process(true)
        return
    var current_scene := get_tree().current_scene
    set_physics_process(false)
    if not MultiplayerGateway.standalone_expedition_id.is_empty():
        MultiplayerGateway.request_expedition_travel(destination_scene)
        return
    if current_scene != null and current_scene.has_node("StoryOpeningWorldSync"):
        EventBus.toast_requested.emit("The next online story region is not available in this pilot yet.")
        return
    if current_scene == null or bool(current_scene.get_meta("portal_load_pending", false)):
        return
    if not ResourceLoader.exists(destination_scene, "PackedScene"):
        EventBus.toast_requested.emit("Destination unavailable. Try again later.")
        return
    transferring = true
    _loading_player = weakref(body)
    _loading_scene = weakref(current_scene)
    current_scene.set_meta("portal_load_pending", true)
    body.set("input_enabled", false)
    body.set("velocity", Vector2.ZERO)
    TouchInput.release()
    AudioDirector.play_variant("portal_transition")
    # Load resources away from the main thread; only instantiate on the main thread.
    var error := ResourceLoader.load_threaded_request(destination_scene, "PackedScene", false)
    if error != OK:
        _recover_transfer("Unable to load the destination. Try the portal again.")
        return
    EventBus.toast_requested.emit("Travelling...")
    set_process(true)

func _process(_delta: float) -> void:
    if not transferring:
        return
    var status := ResourceLoader.load_threaded_get_status(destination_scene)
    if status == ResourceLoader.THREAD_LOAD_IN_PROGRESS:
        return
    set_process(false)
    if status != ResourceLoader.THREAD_LOAD_LOADED:
        _recover_transfer("Unable to load the destination. Try the portal again.")
        return
    var packed := ResourceLoader.load_threaded_get(destination_scene) as PackedScene
    if packed == null:
        _recover_transfer("Destination scene unavailable.")
        return
    _finish_transfer.call_deferred(packed)

func _finish_transfer(packed: PackedScene) -> void:
    var scene = _loading_scene.get_ref() if _loading_scene != null else null
    if not is_instance_valid(scene) or get_tree().current_scene != scene:
        _recover_transfer("")
        return
    pending_arrival = arrival_marker
    var error := get_tree().change_scene_to_packed(packed)
    if error != OK:
        pending_arrival = &""
        _recover_transfer("Unable to enter the destination.")
    else:
        StoryMilestoneTelemetry.record_scene_transition(destination_scene)

func _recover_transfer(message: String) -> void:
    transferring = false
    set_process(false)
    var scene = _loading_scene.get_ref() if _loading_scene != null else null
    var player = _loading_player.get_ref() if _loading_player != null else null
    if is_instance_valid(scene):
        scene.remove_meta("portal_load_pending")
    if is_instance_valid(player):
        player.set("input_enabled", true)
    _loading_player = null
    _loading_scene = null
    if not message.is_empty():
        EventBus.toast_requested.emit(message)

func _story_unlocked() -> bool:
    if not required_story_flag.is_empty() and not bool(GameState.quest_domain.flags.get(required_story_flag, false)):
        return false
    if required_quest.is_empty() or not MultiplayerGateway.standalone_expedition_id.is_empty():
        return true
    if GameState.quest_domain.quest_state(required_quest) == "complete":
        return true
    var visited: Variant = GameState.quest_domain.flags.get("discovered_fast_travel_zones", [])
    if not previously_visited_zone.is_empty() and visited is Array:
        for id in visited:
            if str(id).begins_with("StandaloneZone") and int(str(id).right(2)) >= int(previously_visited_zone.right(2)):
                return true
    return false

func _refresh_route_label() -> void:
    if locked_route_text.is_empty():
        return
    var label := get_parent().get_node_or_null("ContinuationMarker/DestinationName") as Label
    if label == null:
        return
    if not label.has_meta("open_route_text"):
        label.set_meta("open_route_text", label.text)
    label.text = str(label.get_meta("open_route_text")) if _story_unlocked() else locked_route_text
