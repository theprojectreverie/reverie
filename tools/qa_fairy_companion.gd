extends Node
func _ready() -> void:
    call_deferred("run")
func run() -> void:
    var zone = load("res://scenes/world/six_zone_reverie/individual_zones/zone_01_royal_gardens_standalone.tscn").instantiate()
    add_child(zone)
    await get_tree().process_frame
    var p = zone.checkpoint_player
    var fairy = p.get_node_or_null("FairyCompanion")
    if fairy == null:
        print("FAIL missing fairy")
        get_tree().quit(1)
        return
    var sprite = fairy.get_node("AnimatedSprite2D")
    print("FAIRY VISIBLE ",fairy.visible," POSITION ",fairy.position," SCALE ",sprite.scale)
    for direction in [0,2,4,6]:
        p.visual.animator.set_direction(direction)
        await get_tree().process_frame
        print("DIRECTION ",direction," ANIM ",sprite.animation," COUNT ",sprite.sprite_frames.get_frame_count(sprite.animation)," SIZE ",sprite.sprite_frames.get_frame_texture(sprite.animation,0).get_size()," PLAYING ",sprite.is_playing())
    for i in range(6):
        await get_tree().create_timer(0.18).timeout
        print("LOOP FRAME ",sprite.frame)
    var before: Vector2 = fairy.global_position - p.global_position
    p.position += Vector2(90, 45)
    await get_tree().process_frame
    print("FOLLOW OFFSET STABLE ",before.is_equal_approx(fairy.global_position-p.global_position))
    print("FAIRY COLLISION CHILDREN ",fairy.find_children("*","CollisionObject2D",true,false).size())
    get_tree().quit()