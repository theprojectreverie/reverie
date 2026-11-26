extends SceneTree
func _initialize():
 call_deferred("run")
func run():
 var state=root.get_node("GameState")
 state.session_domain.player_region="forsaken_ruins"
 var screen=load("res://scenes/ui/map_screen.tscn").instantiate()
 root.add_child(screen)
 for dimensions in [Vector2i(1280,720),Vector2i(852,393),Vector2i(720,1280)]:
  root.size=dimensions
  for i in range(10):await process_frame
  var visible_rect=root.get_visible_rect()
  var atlas=screen._map_canvas
  var panel=screen._map_layout.get_node("Details")
  print("LAYOUT ",dimensions," logical=",visible_rect.size," atlas=",atlas.get_global_rect()," details=",panel.get_global_rect())
  if not visible_rect.encloses(atlas.get_global_rect()) or not visible_rect.encloses(panel.get_global_rect()):
   push_error("layout outside viewport");quit(1);return
  var region=atlas.get_node("Regions/WillowFields")
  var click=InputEventMouseButton.new()
  click.button_index=MOUSE_BUTTON_LEFT;click.pressed=true;click.position=region.get_global_rect().get_center()
  root.push_input(click,true)
  await process_frame
  click.pressed=false;root.push_input(click,true)
  await process_frame
  if screen._displayed_region_id!="willow_fields":
   push_error("actual region click failed");quit(1);return
  atlas.set_selected_region("forsaken_ruins")
  await process_frame
  if DisplayServer.get_name()!="headless":
   await RenderingServer.frame_post_draw
   root.get_texture().get_image().save_png(OS.get_environment("TEMP")+"/reverie_atlas_"+str(dimensions.x)+".png")
 print("MAP_LAYOUT_PASS")
 screen.queue_free()
 await process_frame
 root.get_node("AudioDirector").stop_all_audio_immediately()
 await create_timer(.4).timeout
 quit(0)