extends SceneTree
func _initialize(): call_deferred("_run")
func _run():
 var layout=load("res://scripts/ui/combat/battlefield_layout_component.gd")
 var expected={"royal_gate":"royal_gate_silver_passage.jpg","willow_fields":"willow_fields.jpg","elderwood_grove":"elderwood_cascades.jpg"}
 for region in expected:
  for id in [region,"six_zone_"+region]:
   var path=layout.battle_background_path_for_region(id)
   assert(path.ends_with(expected[region]),id)
   var tex=load(path) as Texture2D
   assert(tex!=null and tex.get_width()==1344 and tex.get_height()==768,id)
 var groups={"royal_gate_patrol_1":"royal_gate_silver_passage.jpg","royal_gate_patrol_2":"royal_gate_silver_passage.jpg","royal_gate_rainbow_1":"royal_gate_silver_passage.jpg","willow_slime_1":"willow_fields.jpg","willow_mossling_1":"willow_fields.jpg","mirene_encounter":"mirene_illusion_domain.jpg","cassien_encounter":"cassien_guarded_tomb.jpg","revienna_encounter":"ravienna_eternal_eclipse.jpg","tutorial_fairy_spar":"companion_fragmented_memories.jpg","gerald_boss_encounter":"gerald_twilight_battlefield.png","rose_slime_garden_1":"moonlit_royal_garden.png"}
 var field=load("res://scenes/ui/battlefield.tscn").instantiate()
 root.add_child(field)
 field.size=Vector2(1280,720)
 await process_frame
 for id in groups:
  field.arena_id=id
  field._build_environment()
  var art=field.get_node("ArenaArtBackdrop")
  assert(art.visible and art.texture!=null and art.texture.resource_path.ends_with(groups[id]),id)
 field.queue_free()
 await process_frame
 print("REGIONAL BATTLEFIELD ART PASS: 6 region aliases, 11 encounter selections")
 quit()
