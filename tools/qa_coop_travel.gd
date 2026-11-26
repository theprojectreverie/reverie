extends Node
func _ready() -> void:
    call_deferred("run")
func fail(reason: String) -> void:
    print("FAIL ",reason)
    get_tree().quit(1)
func run() -> void:
    AuthGateway.api_base_url = OS.get_environment("QA_API")
    MultiplayerGateway.websocket_url = OS.get_environment("QA_WS")
    if AuthGateway.login(OS.get_environment("QA_NAME"), OS.get_environment("QA_PASSWORD")) != OK:
        fail("login start")
        return
    var result: Array = await AuthGateway.auth_result
    if not bool(result[1]):
        fail("login rejected")
        return
    GameState.quest_domain.flags["tutorial_complete"] = true
    MultiplayerGateway.standalone_expedition_id = OS.get_environment("QA_LOBBY")
    MultiplayerGateway.standalone_expedition_region = "six_zone_royal_gardens"
    var zone = load("res://scenes/world/six_zone_reverie/individual_zones/zone_01_royal_gardens_standalone.tscn").instantiate()
    get_tree().root.add_child(zone)
    get_tree().current_scene = zone
    var sync = zone.get_node_or_null("CoopWorldSync")
    var deadline = Time.get_ticks_msec() + 10000
    while not sync._snapshot_ready or sync.remote_players.size() != 1:
        if Time.get_ticks_msec() > deadline:
            fail("initial snapshot")
            return
        await get_tree().process_frame
    var role = OS.get_environment("QA_ROLE")
    if role == "A":
        await get_tree().create_timer(1.0).timeout
        var err = MultiplayerGateway.request_expedition_travel("res://scenes/world/six_zone_reverie/individual_zones/zone_02_royal_gate_standalone.tscn")
        if err != OK:
            fail("request error")
            return
    deadline = Time.get_ticks_msec() + 13000
    while true:
        var current = get_tree().current_scene
        if current != null and str(current.name) == "StandaloneZone02":
            var next_sync = current.get_node_or_null("CoopWorldSync")
            if next_sync != null and next_sync._snapshot_ready and next_sync.remote_players.size() == 1:
                if current.checkpoint_player.global_position.distance_to(Vector2(0,900)) > 5.0:
                    fail("destination spawn")
                    return
                print("PASS party transferred to Royal Gate, new snapshot and remote avatar ready")
                break
        if Time.get_ticks_msec() > deadline:
            fail("destination scene timeout")
            return
        await get_tree().process_frame
    await get_tree().create_timer(0.5).timeout
    get_tree().quit(0)