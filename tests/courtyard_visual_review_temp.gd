extends SceneTree
func _initialize():
 call_deferred("_run")
func _run():
 var gs=root.get_node("GameState")
 gs.quest_domain.flags["tutorial_complete"]=true
 change_scene_to_file("res://scenes/world/six_zone_reverie/individual_zones/zone_05_forsaken_ruins_standalone.tscn")
 await scene_changed
 for i in range(8): await process_frame
 var zone=current_scene
 var courtyard=zone.get_node("RaviennaCourtyard")
 var player=zone.checkpoint_player
 player.global_position=courtyard.global_position+Vector2(0,95)
 player.input_enabled=false
 zone.get_node("UI").hide()
 var camera=zone.get_node("ZoneCamera")
 camera.position=courtyard.global_position+Vector2(-80,-60)
 camera.zoom=Vector2(0.9,0.9)
 camera.make_current()
 for i in range(12): await process_frame
 await RenderingServer.frame_post_draw
 var img=root.get_texture().get_image()
 print("COURTYARD_CAPTURE ",img.get_size()," ",img.save_png("C:/Users/quoth/Downloads/reverie_courtyard_review.png"))
 quit()
