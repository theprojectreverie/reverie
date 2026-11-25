extends SceneTree
func _initialize():
    call_deferred("run")
func run():
    var packed = load("res://scenes/ui/gacha_screen.tscn")
    if packed == null:
        quit(1)
        return
    var screen = packed.instantiate()
    root.add_child(screen)
    screen._selected_banner = "lily_of_shadows"
    screen._refresh()
    for i in range(5): await process_frame
    var found = false
    for n in screen.find_children("*", "", true, false):
        if n is TextureRect and n.texture != null and n.texture.resource_path == "res://assets/portraits/summon/elathra.png":
            found = true
            print("LIVE PORTRAIT: ", n.texture.resource_path, " SIZE: ", n.texture.get_size())
    print("FEATURED: ", screen._featured_id, " PORTRAIT FOUND: ", found)
    quit(0 if found else 1)