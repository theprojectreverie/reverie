extends SceneTree
func _initialize():call_deferred("_run")
func _run():
 var holder=HBoxContainer.new()
 holder.position=Vector2(40,40)
 holder.add_theme_constant_override("separation",16)
 root.add_child(holder)
 for id in ["kael","gerald","lilith"]:
  for rarity in ["rare","epic"]:
   var card=load("res://scenes/ui/components/summon_result_card.tscn").instantiate()
   card.custom_minimum_size=Vector2(180,286)
   var portrait=card.get_node("Content/Portrait")
   portrait.custom_minimum_size=Vector2(132,198)
   card.setup({"character_id":"upgrade_"+id+"_"+rarity+"_v1","rarity":rarity,"kind":"upgrade_card","card_count":2})
   portrait.show_frame=false
   portrait.show_rarity_effect=false
   holder.add_child(card)
   await process_frame
   assert(portrait.portrait_art.visible)
   assert(portrait.portrait_art.texture.resource_path=="res://assets/portraits/summon/"+id+".png")
   assert(not portrait.portrait_report().fallback_active)
 for i in range(15):await process_frame
 await RenderingServer.frame_post_draw
 assert(root.get_texture().get_image().save_png("C:/Users/quoth/Downloads/reverie_trio_results_review.png")==OK)
 print("PASS actual visible TextureRect: all six cards, no fallback")
 holder.queue_free()
 await process_frame
 quit(0)
