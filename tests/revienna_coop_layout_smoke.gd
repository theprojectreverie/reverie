extends SceneTree
func _initialize():call_deferred("_run")
func _run():
 var panel=load("res://scenes/ui/components/coop_revienna_battle.tscn").instantiate()
 root.add_child(panel)
 for dimensions in [Vector2i(1280,720),Vector2i(390,844),Vector2i(844,390)]:
  root.size=dimensions
  for i in range(12):await process_frame
  var box=panel.get_node("Center/Panel")
  var area=panel.get_global_rect()
  var rect=box.get_global_rect()
  print("LAYOUT ",dimensions," actual ",area," panel ",rect," contained ",area.encloses(rect))
  assert(area.encloses(rect))
  if dimensions.y > dimensions.x:
   assert(rect.size.x >= area.size.x * 0.75)
  else:
   assert(panel.get_node("Center").scale.is_equal_approx(Vector2.ONE))
  await RenderingServer.frame_post_draw
  root.get_texture().get_image().save_png("C:/Users/quoth/Downloads/reverie_coop_layout_"+str(dimensions.x)+".png")
 panel.queue_free()
 await process_frame
 quit(0)
