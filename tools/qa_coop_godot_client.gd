extends Node
func _ready() -> void:
    call_deferred("run")
func fail(reason: String) -> void:
    print("FAIL ",reason)
    get_tree().quit(1)
func run() -> void:
    AuthGateway.api_base_url = OS.get_environment("QA_API")
    MultiplayerGateway.websocket_url = OS.get_environment("QA_WS")
    var err = AuthGateway.login(OS.get_environment("QA_NAME"), OS.get_environment("QA_PASSWORD"))
    if err != OK:
        fail("login start")
        return
    var result: Array = await AuthGateway.auth_result
    if not bool(result[1]):
        fail("login rejected")
        return
    GameState.quest_domain.flags["tutorial_complete"] = true
    MultiplayerGateway.standalone_expedition_id = OS.get_environment("QA_LOBBY")
    var region: String = OS.get_environment("QA_REGION")
    MultiplayerGateway.standalone_expedition_region = region
    var data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://resources/data/six_zone_expeditions.json"))
    var entry: Dictionary = data[region]
    var zone = load(str(entry["scene"])).instantiate()
    add_child(zone)
    var sync = zone.get_node_or_null("CoopWorldSync")
    if sync == null:
        fail("no sync")
        return
    var deadline = Time.get_ticks_msec() + 10000
    while not sync._snapshot_ready or sync.remote_players.size() != 1:
        if Time.get_ticks_msec() > deadline:
            fail("snapshot not ready")
            return
        await get_tree().process_frame
    var p = zone.checkpoint_player
    if p.network_recovery_paused:
        fail("player remained paused")
        return
    var remote = sync.remote_players.values()[0]
    if remote.name_label == null or not remote.display_name.begins_with("Qa"):
        fail("remote identity")
        return
    print("PASS authenticated expedition scene, named remote avatar, movement unlocked")
    await get_tree().create_timer(0.8).timeout
    var base: Vector2 = p.global_position
    var target = base + Vector2(20 if OS.get_environment("QA_ROLE") == "A" else -20,0)
    p.global_position = target
    var expected = Vector2(float(entry["spawn"][0]) + (-20 if OS.get_environment("QA_ROLE") == "A" else 20),float(entry["spawn"][1]))
    deadline = Time.get_ticks_msec() + 7000
    while remote.target_position.distance_to(expected) > 1.0:
        if Time.get_ticks_msec() > deadline:
            fail("remote movement target not received: " + str(remote.target_position))
            return
        await get_tree().process_frame
    print("PASS peer movement arrived ",remote.target_position)
    await get_tree().create_timer(0.6).timeout
    if remote.global_position.distance_to(expected)>3.0:
        fail("remote interpolation")
        return
    print("PASS peer rendered position interpolates to network target")
    for n in (["Crownling1","Crownling2","Crownling3"] if region == "six_zone_royal_gardens" else []):
        if zone.get_node_or_null(n+"/WorldHealth") == null:
            fail("missing Crownling health bar")
            return
    print("PASS all Crownling health nodes")
    get_tree().quit(0)