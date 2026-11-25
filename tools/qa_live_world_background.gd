extends SceneTree
func _initialize():
    call_deferred("run")
func run():
    var err = change_scene_to_file("res://scenes/world/six_zone_reverie/individual_zones/zone_01_royal_gardens_standalone.tscn")
    if err != OK:
        print("SCENE FAILED ", err)
        quit(1)
        return
    for i in range(20): await physics_frame
    var bg = current_scene.get_node_or_null("ScenicBackground") as Sprite2D
    if bg == null or bg.texture == null:
        print("BACKGROUND FAILED")
        quit(2)
        return
    print("LIVE BACKGROUND: ", bg.texture.resource_path, " size=", bg.texture.get_size(), " world=", bg.get_rect().size * bg.scale)
    print("PLAYER: ", get_first_node_in_group("player") != null)
    quit(0)