extends Node
func _ready() -> void:
    call_deferred("run")
func run() -> void:
    var src = SpriteFramesActorSource.register_playable("kael")
    print("VALIDATION ",src.validate_sheets()," REGISTERED ",src.has_frames())
    for state in [0,4,5]:
        for dir in range(8):
            var tex = src.frame(state,dir,0)
            print("STATE ",state," DIR ",dir," COUNT ",src.frame_count(state,dir)," SIZE ",tex.get_size() if tex else Vector2.ZERO," FPS ",src.fps(state))
    var zone = load("res://scenes/world/six_zone_reverie/individual_zones/zone_01_royal_gardens_standalone.tscn").instantiate()
    add_child(zone)
    await get_tree().process_frame
    var v = zone.checkpoint_player.visual
    print("PLAYER ART ",v.character_art_report()," NEW TIMING ",v.animator.kael_combat_frames)
    print("IDLE START ",v.animator.frame," FPS ",v.animator.fps()," COUNT ",v.animator.frame_count())
    for i in range(7):
        await get_tree().create_timer(0.17).timeout
        print("IDLE TICK ",v.animator.state," FRAME ",v.animator.frame)
    v.play_attack()
    print("ATTACK STATE ",v.animator.state," COUNT ",v.animator.frame_count()," FPS ",v.animator.fps())
    await get_tree().create_timer(0.8).timeout
    v.hit()
    print("HIT STATE ",v.animator.state," COUNT ",v.animator.frame_count()," FPS ",v.animator.fps())
    await get_tree().create_timer(0.5).timeout
    print("RETURN STATE ",v.animator.state)
    get_tree().quit()