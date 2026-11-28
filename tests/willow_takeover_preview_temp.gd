extends SceneTree
func _initialize():call_deferred("run")
func run():
 change_scene_to_file("res://scenes/world/six_zone_reverie/individual_zones/zone_03_willow_fields_standalone.tscn")
 await scene_changed
 var z=current_scene
 z.get_node("UI").hide()
 var cam=z.get_node("ZoneCamera")
 z.checkpoint_player.get_node("Camera2D").enabled=false
 cam.enabled=true
 cam.make_current()
 for item in [["willow_latest_overview",Vector2(64,1616),.18],["willow_latest_pavilion",Vector2(1200,1150),.78],["willow_latest_farm",Vector2(-900,1500),.65]]:
  cam.position=item[1];cam.zoom=Vector2.ONE*item[2]
  for i in range(12):await process_frame
  await RenderingServer.frame_post_draw
  root.get_texture().get_image().save_png(OS.get_environment("TEMP")+"/reverie_map_concepts/"+item[0]+".png")
 z.queue_free()
 for i in range(3):await process_frame
 root.get_node("AudioDirector").stop_all_audio_immediately()
 await create_timer(.35).timeout
 quit()
