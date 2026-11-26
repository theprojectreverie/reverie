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
    var nav = load("res://scripts/world/six_zone_reverie/expedition_navigation.gd")
    var guide: Dictionary = nav.resolve(zone)
    if not guide.ready or not guide.valid or not guide.repeatable or guide.complete:
        fail("garden repeatable guidance "+str(guide))
        return
    print("PASS authenticated expedition scene, named remote avatar, movement unlocked, repeatable objective tracked")
    var monster = zone.get_node("RoseSlime1")
    await get_tree().create_timer(0.8).timeout
    if monster.coop_motion_samples < 2 or monster.global_position.distance_to(monster.home) < 0.2 or monster.global_position.distance_to(monster.home) > 10.0:
        fail("bounded server patrol not rendered")
        return
    print("PASS bounded server patrol, received samples: ",monster.coop_motion_samples)
    for step in range(1,6):
        p.global_position = Vector2(-1320+44*step,2325-25*step)
        await get_tree().create_timer(0.24).timeout
    deadline = Time.get_ticks_msec()+4000
    while monster.coop_motion_mode != "pursuit" or monster.coop_aggro_target.is_empty():
        if Time.get_ticks_msec()>deadline:
            fail("monster failed to acquire a nearby player")
            return
        await get_tree().process_frame
    if monster.coop_aggro_target != sync.local_player_id and monster.coop_aggro_target != remote.player_id:
        fail("unknown aggro target")
        return
    if monster.coop_motion_target.distance_to(monster.home)>24.01:
        fail("server monster exceeded leash")
        return
    print("PASS authoritative aggro and bounded pursuit")
    for step in range(4,-1,-1):
        p.global_position = Vector2(-1320+44*step,2325-25*step)
        await get_tree().create_timer(0.24).timeout
    deadline = Time.get_ticks_msec()+5000
    while monster.coop_motion_mode != "patrol" or not monster.coop_aggro_target.is_empty():
        if Time.get_ticks_msec()>deadline:
            fail("monster did not disengage")
            return
        await get_tree().process_frame
    print("PASS enemy disengages and resumes home patrol")
    for step in range(1,6):
        p.global_position = Vector2(-1320+44*step,2325-25*step)
        await get_tree().create_timer(0.24).timeout
    await get_tree().create_timer(1.2 if OS.get_environment("QA_ROLE") == "A" else 1.6).timeout
    monster.receive_world_hit(25.0)
    deadline = Time.get_ticks_msec()+5000
    while monster.world_hp > 50.0:
        if Time.get_ticks_msec()>deadline:
            fail("shared HP timeout: "+str(monster.world_hp))
            return
        await get_tree().process_frame
    if monster.health_bar.value != 50.0 or not monster.health_bar.visible:
        fail("health display")
        return
    print("PASS shared HP and visible health bar at 50")
    if OS.get_environment("QA_ROLE") == "A" and p.get_node("WorldCombatComponent").hp != 88.0:
        fail("server retaliation did not update player health")
        return
    print("PASS server combat health observed: ",p.get_node("WorldCombatComponent").hp)
    if remote.attack_animation_count < 1 or remote.visual.character_id != "kael" or remote.visual.using_temporary_art:
        fail("remote attack sprite registration or animation")
        return
    print("PASS remote Kael uses authored sprites and confirmed attack animation")
    await get_tree().create_timer(1.0 if OS.get_environment("QA_ROLE") == "A" else 1.5).timeout
    monster.receive_world_hit(25.0)
    deadline = Time.get_ticks_msec()+5000
    while not monster.defeated:
        if Time.get_ticks_msec()>deadline:
            fail("defeat timeout: "+str(monster.world_hp))
            return
        await get_tree().process_frame
    if monster.world_hp != 0.0 or monster.health_bar.visible:
        fail("defeat health bar")
        return
    print("PASS synchronized defeat state")
    await get_tree().create_timer(1.2).timeout
    if monster.visible:
        fail("defeat animation did not hide monster")
        return
    print("PASS defeat animation completes and monster disappears")
    deadline = Time.get_ticks_msec()+5000
    while int(AuthGateway.online_wallet.get("gold",-1)) != 15 or int(AuthGateway.online_wallet.get("xp",-1)) != 10:
        if Time.get_ticks_msec()>deadline:
            fail("wallet not synchronized")
            return
        await get_tree().process_frame
    var hud = zone.get_node("UI/HUD")
    await get_tree().process_frame
    var texts: Array = []
    for chip in hud._currency_box.get_children():
        texts.append(chip.get_node("Content/ValueLabel").text)
    if not texts.has("Online gold: 15") or not texts.has("Online XP: 10"):
        fail("wallet HUD display: "+str(texts))
        return
    print("PASS online wallet HUD displays persistent gold and XP")
    AuthGateway.online_wallet.clear()
    AuthGateway.refresh_online_wallet()
    deadline = Time.get_ticks_msec()+5000
    while AuthGateway.online_wallet.is_empty():
        if Time.get_ticks_msec()>deadline:
            fail("wallet reload timeout")
            return
        await get_tree().process_frame
    if AuthGateway.online_wallet != {"gold":15,"xp":10}:
        fail("wallet persistence")
        return
    print("PASS authoritative wallet reload after clearing client cache")
    if int(AuthGateway.online_inventory.get("glade_sap",0)) != 1:
        fail("missing individual material drop")
        return
    print("PASS individual Glade Sap drop recovered from server")
    get_tree().quit(0)