extends SceneTree
func _initialize(): call_deferred("_run")
func _run():
 var layout = load("res://scripts/ui/combat/battlefield_layout_component.gd")
 var field = load("res://scenes/ui/battlefield.tscn").instantiate()
 field.arena_id = "mirene_encounter"
 root.add_child(field)
 field.size = Vector2(1280,720)
 await process_frame
 var art = field.get_node("ArenaArtBackdrop")
 assert(art.visible and art.texture != null)
 assert(art.texture.resource_path.ends_with("mirene_illusion_domain.jpg"))
 assert(art.texture.get_width()==1344 and art.texture.get_height()==768)
 assert(layout.battle_background_path_for_group("rose_slime_garden_1").ends_with("moonlit_royal_garden.png"))
 field.arena_id = "rose_slime_garden_1"
 field._build_environment()
 assert(art.visible and art.texture.resource_path.ends_with("moonlit_royal_garden.png"))
 field.queue_free()
 await process_frame
 print("MIRENE APPROVED BATTLEFIELD AND NORMAL GARDENS PASS")
 quit()
