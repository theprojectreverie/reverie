extends SceneTree
func _initialize(): call_deferred("_run")
func _run():
 if OS.get_environment("REVERIE_E2E_DISABLE_LOCAL_SAVE")!="1":
  quit(2)
  return
 var gs=root.get_node("GameState")
 gs.quest_domain.flags["tutorial_complete"]=true
 change_scene_to_file("res://scenes/world/six_zone_reverie/individual_zones/zone_05_forsaken_ruins_standalone.tscn")
 await scene_changed
 for i in range(10): await process_frame
 var zone=current_scene
 var hud=zone.get_node("UI/HUD")
 var router=zone.get_node("OverlayRouter")
 var player=zone.checkpoint_player
 assert(hud.visible and player.input_enabled)
 for id in ["gacha","inventory","collection","quests"]:
  hud.screen_requested.emit(id)
  await process_frame
  assert(is_instance_valid(router.active_overlay),"Failed to open "+id)
  assert(not hud.is_visible_in_tree(),"HUD visible on "+id)
  assert(not player.input_enabled)
  router.close_active()
  await process_frame
  assert(router.active_overlay==null and hud.visible and player.input_enabled,"Failed restore "+id)
  print("HUD MODAL PASS ",id)
 hud.menu_requested.emit()
 await process_frame
 assert(router.active_overlay!=null and not hud.visible)
 router.close_active()
 await process_frame
 assert(hud.visible and player.input_enabled)
 hud.hide()
 assert(router.open_screen("gacha"))
 router.close_active()
 await process_frame
 assert(not hud.visible,"Originally hidden HUD should stay hidden")
 print("PAUSE AND PREVIOUS VISIBILITY PASS")
 zone.queue_free()
 for i in range(4):await process_frame
 root.get_node("AudioDirector").stop_all_audio_immediately()
 await create_timer(.35).timeout
 quit()
