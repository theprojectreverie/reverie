extends SceneTree
func _initialize():
 call_deferred("_run")
func _run():
 if OS.get_environment("REVERIE_E2E_DISABLE_LOCAL_SAVE")!="1":
  quit(2)
  return
 root.size=Vector2i(390,844)
 var gs=root.get_node("GameState")
 gs.quest_domain.flags["tutorial_complete"]=true
 change_scene_to_file("res://scenes/world/six_zone_reverie/individual_zones/zone_05_forsaken_ruins_standalone.tscn")
 await scene_changed
 for i in range(8): await process_frame
 var zone=current_scene
 gs.quest_domain.advance_quest("cassien_resurrection")
 gs.quest_domain.start_quest("forsaken_braziers")
 for i in range(3): gs.quest_domain.advance_quest("forsaken_braziers")
 gs.quest_domain.complete_quest("forsaken_braziers")
 var cassien=zone.get_node("CassienRitual")
 var player=zone.checkpoint_player
 cassien.awakened=true
 cassien.cassien_visual.stop()
 cassien.cassien_visual.animation=&"awakening"
 cassien.cassien_visual.frame=15
 player.global_position=cassien.global_position+Vector2(0,90)
 await create_timer(0.6).timeout
 cassien.interact()
 var dialog=zone.get_node("UI/Dialogue")
 assert(dialog.visible)
 dialog._show_node("departure")
 dialog._finish_typing()
 cassien.tomb_animation.advance(0.55)
 for i in range(4): await physics_frame
 print("CAMERA ",root.get_camera_2d().name," zoom ",root.get_camera_2d().zoom," center ",root.get_camera_2d().get_screen_center_position())
 await RenderingServer.frame_post_draw
 var img=root.get_texture().get_image()
 print("VIEWPORT ",root.get_visible_rect().size," PANEL ",dialog.get_node("DialoguePanel").get_global_rect()); print("RITUAL_CAPTURE ",img.get_size()," ",img.save_png("C:/Users/quoth/Downloads/reverie_ritual_mobile_choice.png"))
 var panel=dialog.get_node("DialoguePanel")
 var choice=dialog.get_node("DialoguePanel/ContentRow/TextColumn/ChoicesBox").get_child(0)
 assert(dialog.ritual_portrait_layout and panel.offset_top==-740.0)
 assert(choice.size.y>=140 and choice.get_global_rect().end.x<=panel.get_global_rect().end.x)
 assert(root.get_camera_2d()==cassien.ritual_camera and not zone.get_node("UI/HUD").visible)
 choice.pressed.emit()
 await cassien.departure_finished
 for i in range(4): await process_frame
 assert(gs.quest_domain.flags.get("ravienna_resurrected",false))
 assert(not dialog.ritual_portrait_layout and panel.offset_top==-314.0)
 assert(root.get_camera_2d()==player.get_node("Camera2D") and zone.get_node("UI/HUD").visible)
 print("PORTRAIT RITUAL TOUCH CHOICE AND LAYOUT RESTORATION PASS")
 root.get_node("AudioDirector").stop_all_audio_immediately()
 await create_timer(0.35).timeout
 quit()
