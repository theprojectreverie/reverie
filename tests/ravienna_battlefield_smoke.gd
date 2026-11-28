extends SceneTree
func _initialize(): call_deferred("_run")
func _run():
 var layout = load("res://scripts/ui/combat/battlefield_layout_component.gd")
 var field = load("res://scenes/ui/battlefield.tscn").instantiate()
 field.arena_id = "revienna_encounter"
 root.add_child(field)
 field.size = Vector2(1280,720)
 await process_frame
 var art = field.get_node("ArenaArtBackdrop")
 assert(art.visible and art.texture != null)
 assert(art.texture.resource_path.ends_with("ravienna_eternal_eclipse.jpg"))
 assert(art.texture.get_width()==1344 and art.texture.get_height()==768)
 assert(layout.battle_background_path_for_group("baltoria_encounter").ends_with("gothic_cathedral_hall.png"))
 assert(layout.battle_background_path_for_group("cassien_encounter").ends_with("cassien_guarded_tomb.jpg"))
 assert(layout.battle_background_path_for_group("mirene_encounter").ends_with("mirene_illusion_domain.jpg"))
 assert(layout.battle_background_path_for_group("tutorial_fairy_spar").ends_with("companion_fragmented_memories.jpg"))
 field.queue_free()
 await process_frame
 print("RAVIENNA ETERNAL ECLIPSE BATTLEFIELD PASS")
 quit()
