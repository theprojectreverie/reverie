extends Node
func _ready() -> void:
    call_deferred("run")
func run() -> void:
    var zone = load("res://scenes/world/six_zone_reverie/individual_zones/zone_01_royal_gardens_standalone.tscn").instantiate()
    add_child(zone)
    await get_tree().process_frame
    var sync := CoopWorldSyncComponent.new()
    zone.add_child(sync)
    sync.bind_standalone(zone, zone.checkpoint_player, "six_zone_royal_gardens")
    sync.local_player_id = "qa_local"
    var ok = sync._apply_snapshot({"members":[{"region_id":"six_zone_royal_gardens","id":"qa_local","name":"Local","x":-1320,"y":2325},{"region_id":"six_zone_royal_gardens","id":"qa_remote","name":"Remote","x":-1280,"y":2300}],"sequence":1})
    var remote = sync.remote_players.get("qa_remote")
    print("SNAPSHOT ",ok," REMOTE COUNT ",sync.remote_players.size()," LOCAL POSITION ",zone.checkpoint_player.global_position)
    sync._apply_live_event_now({"type":"position","playerId":"qa_remote","x":-1250,"y":2290,"sequence":2})
    var moved: bool = remote != null and remote.target_position == Vector2(-1250,2290)
    print("REMOTE MOVEMENT ",moved)
    sync._apply_live_event_now({"type":"player_left","playerId":"qa_remote","sequence":3})
    print("REMOTE REMOVAL ",sync.remote_players.is_empty())
    get_tree().quit(0 if ok and moved and sync.remote_players.is_empty() else 1)