extends SceneTree
func _initialize():call_deferred("_run")
func _run():
 if OS.get_environment("REVERIE_E2E_DISABLE_LOCAL_SAVE")!="1":
  quit(2)
  return
 var gs=root.get_node("GameState")
 gs.new_game("Lazy loading QA")
 gs.flags["tutorial_complete"]=true
 gs.flags["village_gerald_defeated"]=true
 change_scene_to_file("res://scenes/world/six_zone_reverie/individual_zones/zone_05_forsaken_ruins_standalone.tscn")
 await scene_changed
 for i in range(8):await process_frame
 var router=current_scene.get_node("OverlayRouter")
 var binding=current_scene.get_node("ZoneUIBinding")
 var p=current_scene.checkpoint_player
 for id in ["collection","inventory","quests","map","gacha","chat","social","shop","settings"]:
  binding._open_screen(id)
  if router.active_overlay==null:
   push_error("OPEN FAILED "+id)
   quit(1)
   return
  var w=weakref(router.active_overlay)
  if p.input_enabled:
   quit(1)
   return
  await process_frame
  router.close_active()
  for i in range(5):await process_frame
  if w.get_ref()!=null or router.active_overlay!=null or not p.input_enabled:
   push_error("CLOSE FAILED "+id)
   quit(1)
   return
  print("LAZY OVERLAY PASS ",id)
 binding._open_pause()
 assert(router.active_overlay!=null and not p.input_enabled)
 router.close_active()
 await process_frame
 assert(p.input_enabled)
 var combat=current_scene.get_node("CombatRouter")
 assert(combat.start_encounter("cassien_encounter"))
 await process_frame
 assert(combat.active_combat!=null and combat.active_combat.engine!=null)
 combat.active_combat._claim(false)
 for i in range(5):await process_frame
 assert(combat.active_combat==null)
 print("LAZY COMBAT AND PAUSE PASS")
 change_scene_to_file("res://scenes/ui/main_menu.tscn")
 await scene_changed
 for i in range(3):await process_frame
 var menu=current_scene
 for pair in [["open_inventory","InventoryOverlay"],["open_summon","SummonOverlay"],["open_world_map","WorldMapOverlay"],["open_daily_rewards","DailyRewardsOverlay"]]:
  menu.overlays.call(pair[0])
  var o=menu.get_node_or_null(pair[1])
  assert(o!=null)
  if o.has_method("close_screen"):o.close_screen()
  else:o.queue_free()
  for i in range(4):await process_frame
  assert(not menu.has_node(pair[1]))
  print("LAZY MENU PASS ",pair[1])
 menu.queue_free()
 await process_frame
 root.get_node("AudioDirector").stop_all_audio_immediately()
 await create_timer(.4).timeout
 print("LAZY LOADING ALL PASS")
 quit()
