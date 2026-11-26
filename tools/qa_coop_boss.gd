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
    var boss = zone.get_node("ReviennaEncounter")
    if p.global_position.distance_to(boss.global_position)>150:
        fail("boss test spawn out of range")
        return
    boss._open_coop_panel()
    if not is_instance_valid(boss.coop_panel):
        fail("boss panel missing")
        return
    var panel = boss.coop_panel.get_node("Center/Panel/Content")
    var art = boss.coop_panel.art
    var clips := {}
    var eclipse_impact := [false]
    boss.coop_panel.eruption.visibility_changed.connect(func():
        if boss.coop_panel.eruption.visible:
            eclipse_impact[0] = true
    )
    art.animation_changed.connect(func(): clips[str(art.animation)] = true)
    var phases := {}
    var strike = panel.get_node("Attack")
    await get_tree().create_timer(0.6 if OS.get_environment("QA_ROLE") == "A" else 0.9).timeout
    var disconnected_once := false
    deadline = Time.get_ticks_msec()+35000
    while not boss.defeated:
        if Time.get_ticks_msec()>deadline:
            fail("boss encounter timeout, hp="+str(boss.coop_hp))
            return
        if OS.get_environment("QA_ROLE") == "A" and not disconnected_once and not boss.coop_warning.is_empty() and boss.coop_hp <= 1200:
            disconnected_once = true
            var saved_hp: float = boss.coop_hp
            var saved_phase: int = boss.coop_phase
            MultiplayerGateway._peer.close(1000, "QA reconnect")
            var reconnect_deadline := Time.get_ticks_msec()+8000
            var saw_pause := false
            while true:
                await get_tree().process_frame
                if not sync._snapshot_ready:
                    saw_pause = true
                    if not strike.disabled:
                        await get_tree().process_frame
                    if not strike.disabled:
                        fail("strike enabled while disconnected")
                        return
                if saw_pause and sync._snapshot_ready and MultiplayerGateway.is_connected_to_lobby():
                    break
                if Time.get_ticks_msec()>reconnect_deadline:
                    fail("reconnect did not restore snapshot")
                    return
            if boss.coop_hp > saved_hp or boss.coop_phase < saved_phase or not is_instance_valid(boss.coop_panel):
                fail("boss state regressed on reconnect")
                return
            print("PASS reconnect restored boss HP, phase and battle screen")
        if not boss.coop_warning.is_empty():
            if not panel.get_node("Warning").text.contains(str(boss.coop_warning.get("name"))):
                fail("missing special attack warning")
                return
            if boss._is_warning_target() and boss.coop_guard_ack != int(boss.coop_warning.get("resolveAt",-1)):
                if panel.get_node("Guard").disabled:
                    fail("target guard unavailable")
                    return
                panel.get_node("Guard").pressed.emit()
        else:
            strike.pressed.emit()
        await get_tree().create_timer(0.65).timeout
        phases[boss.coop_phase]=true
        if absf(panel.get_node("PlayerHealth").value-p.get_node("WorldCombatComponent").hp)>0.1:
            fail("player HP display mismatch")
            return
        if absf(panel.get_node("Health").value-boss.coop_hp)>0.1:
            fail("boss HP display mismatch")
            return
    if boss.coop_hp != 0.0 or not strike.disabled or panel.get_node("Phase").text != "Victory" or phases.size()!=3:
        fail("boss victory or phases: "+str(phases))
        return
    if OS.get_environment("QA_ROLE") == "A" and not disconnected_once:
        fail("reconnect scenario not exercised")
        return
    print("PASS all three boss phases, shared HP, player health display, victory display, strike disabled")
    if boss.coop_special_count < 1 or boss.coop_guard_count < 1:
        fail("special attack or guard not synchronized")
        return
    print("PASS synchronized special warnings and guard resolution: ",boss.coop_guard_count)
    deadline = Time.get_ticks_msec()+5000
    while int(AuthGateway.online_wallet.get("gold",0))!=2000 or int(AuthGateway.online_wallet.get("xp",0))!=3000:
        if Time.get_ticks_msec()>deadline:
            fail("boss wallet rewards")
            return
        await get_tree().process_frame
    if int(AuthGateway.online_inventory.get("gothic_shard",0)) != 4:
        fail("boss loot reward")
        return
    if int(AuthGateway.online_currencies.get("crystals",0)) != 400 or int(AuthGateway.online_currencies.get("ancient_coins",0)) != 5:
        fail("missing boss bonus currencies")
        return
    print("PASS persistent individual boss rewards, including crystals and ancient coins")
    if art.animation != &"defeat":
        fail("missing authored defeat pose")
        return
    if art.is_playing():
        await art.animation_finished
    if art.frame != art.sprite_frames.get_frame_count(&"defeat") - 1:
        fail("defeat did not finish")
        return
    if not clips.has("hit") or not clips.has("shadow_lash") or not clips.has("hollow_wail") or not clips.has("ravienna_eclipse") or not eclipse_impact[0]:
        fail("missing server-confirmed combat clips "+str(clips))
        return
    print("PASS authored live combat clips and final kneeling pose ",clips)
    panel.get_node("Leave").pressed.emit()
    await get_tree().process_frame
    if is_instance_valid(boss.coop_panel) or not p.input_enabled or bool(zone.get_meta("coop_boss_panel_open",false)):
        fail("boss exit did not restore exploration")
        return
    var nav = load("res://scripts/world/six_zone_reverie/expedition_navigation.gd")
    var guide: Dictionary = nav.resolve(zone)
    if not guide.ready or not guide.complete or guide.valid or not guide.rows[0].done:
        fail("tower completed guidance "+str(guide))
        return
    print("PASS battle exit restores exploration and expedition journal shows victory")
    get_tree().quit(0)