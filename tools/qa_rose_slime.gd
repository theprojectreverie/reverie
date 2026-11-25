extends Node
func _ready() -> void:
    call_deferred("run")
func run() -> void:
    var zone = load("res://scenes/world/six_zone_reverie/individual_zones/zone_01_royal_gardens_standalone.tscn").instantiate()
    add_child(zone)
    await get_tree().physics_frame
    await get_tree().physics_frame
    for i in range(1,7):
        var slime = zone.get_node("RoseSlime%d" % i)
        var q = PhysicsPointQueryParameters2D.new()
        q.position = slime.global_position
        q.collision_mask = 1
        print("SPAWN ", i, " ", slime.position, " blocked=", not slime.get_world_2d().direct_space_state.intersect_point(q,1).is_empty(), " frames=", slime.sprite.sprite_frames.get_frame_count("idle"))
    var slime = zone.get_node("RoseSlime1")
    zone.checkpoint_player.position = slime.position + Vector2(35,0)
    zone.checkpoint_player.get_node("InteractionComponent").refresh_nearest()
    print("PROMPT ",zone.checkpoint_player.current_prompt())
    slime.interact()
    await get_tree().process_frame
    await get_tree().process_frame
    var combat = zone.get_node("CombatRouter").active_combat
    print("COMBAT OPEN ",is_instance_valid(combat)," PLAYER INPUT ",zone.checkpoint_player.input_enabled)
    if is_instance_valid(combat):
        for actor in combat.find_children("*","Node2D",true,false):
            if actor is BattlefieldActor and actor.unit != null and actor.unit.def_id == "rose_slime":
                print("BATTLE ART ",is_instance_valid(actor.rose_art))
                actor.play_attack()
                print("ATTACK ",actor.rose_art.animation)
                actor.take_hit()
                print("HIT ",actor.rose_art.animation)
                actor.play_death()
                print("DEFEAT ",actor.rose_art.animation)
    slime.respawn_seconds = 1.0
    slime._on_battle_finished({"group_id": slime.group_id, "victory": true})
    await get_tree().create_timer(1.0).timeout
    print("WORLD DEFEAT ",slime.defeated," HIDDEN ",not slime.visible)
    await get_tree().create_timer(1.0).timeout
    print("RESPAWN ", not slime.defeated," VISIBLE ",slime.visible," INTERACTABLE ",slime.can_interact()," ANIM ",slime.sprite.animation)
    get_tree().quit()