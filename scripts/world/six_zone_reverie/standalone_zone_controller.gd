extends Node2D

## Standalone six-zone preview controller: supplies a player and places it at the
## destination road's safe approach, rather than on top of its transfer trigger.
const PLAYER_SCENE: PackedScene = preload("res://scenes/characters/player.tscn")
const TRANSFER_SCRIPT = preload("res://scripts/world/six_zone_reverie/zone_transfer_trigger.gd")

@export var player_size_multiplier: float = 1.0
@export var player_speed_multiplier: float = 1.0
@export var player_start_zoom: float = 1.15

const FAST_TRAVEL = preload("res://scripts/world/six_zone_reverie/fast_travel.gd")
const CHECKPOINT = preload("res://scripts/world/six_zone_reverie/six_zone_checkpoint.gd")
var checkpoint_player: CharacterBody2D
var checkpoint_elapsed := 0.0
var interaction_prompt_elapsed := 0.1

func _ready() -> void:
    var region: String = {"StandaloneVillage": "greenward", "StandaloneZone01": "castle_royal_gardens", "StandaloneZone02": "royal_gate", "StandaloneZone04": "elderwood_grove", "StandaloneZone05": "forsaken_ruins", "StandaloneZone06": "gothic_castle_boss_zone"}.get(str(name), "")
    AudioDirector.sync_region_ambience(region)
    if name == &"StandaloneVillage":
        AudioDirector.play_track("gerald_childhood", 1.0)
    if has_node("NPCDialogueLayer/Dialogue"):
        EventBus.dialogue_requested.connect(_open_local_npc_dialogue)
        EventBus.dialogue_finished.connect(_on_local_dialogue_finished)
    var player: CharacterBody2D = PLAYER_SCENE.instantiate()
    var arrival: StringName = TRANSFER_SCRIPT.pending_arrival
    TRANSFER_SCRIPT.pending_arrival = &""
    var marker: Marker2D = get_node_or_null("TransferPoints/" + String(arrival)) as Marker2D
    if marker == null:
        marker = get_node_or_null("TransferPoints/ToPreviousZone") as Marker2D
    if marker == null:
        marker = get_node_or_null("TransferPoints/ToNextZone") as Marker2D
    var is_royal_gardens := name == "StandaloneZone01"
    var fresh_garden_start := is_royal_gardens and arrival == &""
    var spawn_at := Vector2(0, 1450)
    if fresh_garden_start:
        marker = null
        spawn_at = $TransferPoints/GardenEntrance.position
    if marker != null:
        # Place the arriving player away from the trigger to prevent bounce-back.
        spawn_at = marker.position + (Vector2(0, 180) if arrival == &"ToPreviousZone" else Vector2(0, -180))
    # An optional editor-positioned safe spawn is more accurate on diagonal isometric roads
    # than applying a vertical offset to a transfer marker. Zones without these nodes
    # retain their original arrival behavior.
    var safe_name := "SafeSpawnFromNextZone" if arrival == &"ToNextZone" else "SafeSpawnFromPreviousZone"
    var safe_marker := get_node_or_null("TransferPoints/" + safe_name) as Marker2D
    if safe_marker != null:
        spawn_at = safe_marker.position
    if arrival == &"FastTravel":
        var destination := get_node_or_null("TransferPoints/FastTravelArrival") as Marker2D
        if destination != null:
            spawn_at = destination.position
    player.position = CHECKPOINT.restore(self, spawn_at, arrival)
    add_child(player)
    checkpoint_player = player
    var story_sync = preload("res://scripts/online/story_opening_world_sync.gd")
    if name == "StandaloneVillage" and story_sync.pilot_enabled():
        var sync = story_sync.new()
        sync.name = "StoryOpeningWorldSync"
        add_child(sync)
        sync.bind_player(player, "story_village")
        if OS.get_environment("REVERIE_VILLAGE_PROGRESSION_PILOT") == "1":
            var village_sync = preload("res://scripts/online/story_village_progression_sync.gd").new()
            village_sync.name = "StoryVillageProgressionSync"
            add_child(village_sync)
            village_sync.bind(sync)

    elif name == &"StandaloneVillage" and preload("res://scripts/online/story_village_progression_sync.gd").use_public_solo(OS.has_feature("reverie_public_alpha"), AuthGateway.is_authenticated(), not MultiplayerGateway.standalone_expedition_id.is_empty(), bool(GameState.quest_domain.flags.get("village_gerald_defeated", false))):
        # Preserve completed legacy chapters; never erase local story saves.
        var village_sync = preload("res://scripts/online/story_village_progression_sync.gd").new()
        village_sync.name = "StoryVillageProgressionSync"
        add_child(village_sync)
        village_sync.bind(null, true)

    elif (is_royal_gardens or name == &"StandaloneZone02") and story_sync.pilot_enabled() and OS.get_environment("REVERIE_GARDENS_STORY_PILOT") == "1" and MultiplayerGateway.standalone_expedition_id.is_empty():
        var sync = story_sync.new()
        sync.name = "StoryOpeningWorldSync"
        add_child(sync)
        sync.bind_player(player, "story_royal_gardens" if is_royal_gardens else "story_royal_gate")
        var monsters = preload("res://scripts/online/story_garden_combat_sync.gd").new()
        monsters.name = "StoryGardenCombatSync"
        add_child(monsters)
        if not has_node("CombatRouter"):
            var router := GameCombatRouterComponent.new()
            router.name = "CombatRouter"
            add_child(router)
        monsters.bind(self, sync, player)
    var expeditions: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://resources/data/six_zone_expeditions.json"))
    var coop_region: String = MultiplayerGateway.standalone_expedition_region
    if not MultiplayerGateway.standalone_expedition_id.is_empty() and expeditions.has(coop_region) and str(expeditions[coop_region]["node"]) == str(name):
        var sync := CoopWorldSyncComponent.new()
        sync.name = "CoopWorldSync"
        add_child(sync)
        sync.bind_standalone(self, player, coop_region)
        player.set_network_recovery_paused(true)
        MultiplayerGateway.connect_to_lobby(MultiplayerGateway.standalone_expedition_id)
    var fairy_scene: PackedScene = load("res://scenes/characters/components/fairy_companion.tscn")
    if fairy_scene != null and bool(GameState.quest_domain.flags.get("tutorial_complete", false)):
        player.add_child(fairy_scene.instantiate())
    if MultiplayerGateway.standalone_expedition_id.is_empty() and not has_node("StoryGardenCombatSync"):
        if bool(GameState.quest_domain.flags.get("tutorial_complete", false)):
            if not region.is_empty():
                GameState.session_domain.set_player_region(region)
            if name == &"StandaloneZone04":
                GameState.quest_domain.start_quest("elderwood_relics")
            elif name == &"StandaloneZone05":
                GameState.quest_domain.start_quest("cassien_resurrection")
        FAST_TRAVEL.record_visit(self)
        CHECKPOINT.capture(self, player, true)
        EventBus.party_changed.emit.call_deferred()
    if is_royal_gardens or name == "StandaloneZone02" or name == "StandaloneVillage":
        player.scale = Vector2(0.34, 0.34) * player_size_multiplier
        var locomotion := player.get_node("LocomotionComponent") as PlayerLocomotionComponent
        locomotion.movement_speed_multiplier = player_speed_multiplier
        var player_camera := player.get_node("Camera2D") as PlayerCameraRig
        player_camera.scene_min_zoom = 0.86
        player_camera.offset = Vector2(0, 0) if name == "StandaloneVillage" else Vector2(0, 160)
        player_camera.set_base_zoom(player_start_zoom)
        if name == "StandaloneVillage":
            # Follow the existing rectangular village perimeter, without changing the spawn or terrain.
            var perimeter := get_node_or_null("Perimeter/Bounds") as CollisionPolygon2D
            if perimeter != null and not perimeter.polygon.is_empty():
                var bounds := Rect2(perimeter.to_global(perimeter.polygon[0]), Vector2.ZERO)
                for vertex in perimeter.polygon:
                    bounds = bounds.expand(perimeter.to_global(vertex))
                player_camera.set_world_bounds(bounds.position, bounds.end)
        player_camera.make_current()
        player_camera.reset_smoothing()

func _open_local_npc_dialogue(id: String) -> void:
    if id != "elathra":
        return
    var dialogue = get_node_or_null("NPCDialogueLayer/Dialogue")
    if dialogue == null or dialogue.visible:
        return
    var story = get_node_or_null("StoryGardenCombatSync")
    if story != null:
        var npc = get_node_or_null("Zone/RoyalGardenV3Decorations/Elathra")
        if not story.can_open_audience() or npc == null or checkpoint_player.global_position.distance_to(npc.global_position)>npc.interaction_radius:
            EventBus.toast_requested.emit("Connect to the story server and approach Elathra.")
            if npc != null:npc.talking = false
            return
        dialogue.open_story(story)
    else:
        dialogue.open(id)
    if dialogue.visible and is_instance_valid(checkpoint_player):
        checkpoint_player.set("input_enabled", false)

func _on_local_dialogue_finished(_id: String) -> void:
    if is_instance_valid(checkpoint_player):
        checkpoint_player.set("input_enabled", true)

func _input(event: InputEvent) -> void:
    var dialogue = get_node_or_null("NPCDialogueLayer/Dialogue")
    if dialogue == null or dialogue.visible or not is_instance_valid(checkpoint_player) or not checkpoint_player.input_enabled:
        return
    var npc := get_node_or_null("Zone/RoyalGardenV3Decorations/Elathra") as Interactable
    if npc == null or not npc.can_interact():
        return
    if checkpoint_player.global_position.distance_to(npc.global_position) > npc.interaction_radius:
        return
    var pressed := event.is_action_pressed("interact") and not event.is_echo()
    if event is InputEventKey and event.pressed and not event.echo:
        pressed = pressed or event.physical_keycode == KEY_E or event.keycode == KEY_E
    if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
        var local := npc.to_local(npc.get_global_mouse_position())
        pressed = pressed or Rect2(-64, -128, 128, 128).has_point(local)
    if pressed:
        npc.interact()
        get_viewport().set_input_as_handled()

func _process(delta: float) -> void:
    interaction_prompt_elapsed += delta
    if interaction_prompt_elapsed >= 0.1:
        interaction_prompt_elapsed = 0.0
        _refresh_interaction_prompt()
    checkpoint_elapsed += delta
    if checkpoint_elapsed >= 2.0:
        checkpoint_elapsed = 0.0
        if MultiplayerGateway.standalone_expedition_id.is_empty():
            CHECKPOINT.capture(self, checkpoint_player)

func _notification(what: int) -> void:
    if what == NOTIFICATION_WM_CLOSE_REQUEST or what == NOTIFICATION_APPLICATION_PAUSED:
        if MultiplayerGateway.standalone_expedition_id.is_empty():
            CHECKPOINT.capture(self, checkpoint_player, true)

func _refresh_interaction_prompt() -> void:
    var hint := get_node_or_null("NPCDialogueLayer/InteractionPrompt") as Label
    if hint == null:
        return
    var dialogue := get_node_or_null("NPCDialogueLayer/Dialogue") as Control
    if not is_instance_valid(checkpoint_player) or (dialogue != null and dialogue.visible):
        hint.hide()
        return
    var nearest: Interactable
    var best := INF
    for candidate in get_tree().get_nodes_in_group("interactables"):
        var npc := candidate as Interactable
        if npc == null or not npc.can_interact() or not (npc.is_in_group("world_minimap_npcs") or npc.is_in_group("world_minimap_monsters") or npc.is_in_group("world_minimap_waypoints")):
            continue
        var distance := checkpoint_player.global_position.distance_to(npc.global_position)
        if distance <= npc.interaction_radius and distance < best:
            nearest = npc
            best = distance
    if nearest != null:
        hint.text = "Press E to " + nearest.prompt.substr(0, 1).to_lower() + nearest.prompt.substr(1)
        hint.show()
    else:
        hint.hide()
