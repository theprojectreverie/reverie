extends SceneTree
func _initialize(): call_deferred("_run")
func _run():
 var layout = load("res://scripts/ui/combat/battlefield_layout_component.gd")
 var field = load("res://scenes/ui/battlefield.tscn").instantiate()
 field.arena_id = "tutorial_fairy_spar"
 root.add_child(field)
 field.size = Vector2(1280,720)
 await process_frame
 var art = field.get_node("ArenaArtBackdrop")
 assert(art.visible and art.texture != null)
 assert(art.texture.resource_path.ends_with("companion_fragmented_memories.jpg"))
 assert(art.texture.get_width()==1344 and art.texture.get_height()==768)
 assert(layout.battle_background_path_for_group("royal_road_ambush").ends_with("frozen_castle_courtyard.png"))
 assert(layout.battle_background_path_for_group("mirene_encounter").ends_with("mirene_illusion_domain.jpg"))
 field.queue_free()
 await process_frame
 print("COMPANION MEMORY BATTLEFIELD PASS")
 quit()
