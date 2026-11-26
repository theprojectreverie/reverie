extends SceneTree
func _initialize():
 call_deferred("_run")
func _run():
 if OS.get_environment("REVERIE_E2E_DISABLE_LOCAL_SAVE")!="1":
  quit(2)
  return
 var gs=root.get_node("GameState")
 gs.quest_domain.flags["tutorial_complete"]=true
 gs.quest_domain.flags["village_gerald_defeated"]=true
 gs.quest_domain.flags["discovered_fast_travel_zones"]=["StandaloneVillage","StandaloneZone01","StandaloneZone02","StandaloneZone03","StandaloneZone04","StandaloneZone05","StandaloneZone06"]
 root.get_node("TouchInput").using_touch=true
 change_scene_to_file("res://scenes/world/six_zone_reverie/individual_zones/zone_01_royal_gardens_standalone.tscn")
 await scene_changed
 for f in range(5): await physics_frame
 var route=["StandaloneZone01","StandaloneZone02","StandaloneZone03","StandaloneZone04","StandaloneZone05","StandaloneZone06","StandaloneZone05","StandaloneZone04","StandaloneZone03","StandaloneZone02","StandaloneZone01"]
 for i in range(route.size()-1):
  var zone=current_scene
  assert(zone.name==route[i])
  var player=zone.checkpoint_player
  var map=zone.get_node("UI/HUD/Minimap")
  assert(maxi(map._art_viewport.size.x,map._art_viewport.size.y)<=1024)
  var marker=zone.get_node("TransferPoints/"+("ToNextZone" if i<5 else "ToPreviousZone"))
  var trigger
  for child in marker.get_children():
   if child is Area2D and "destination_scene" in child: trigger=child
  assert(trigger!=null)
  if i==0:
   var original=trigger.destination_scene
   trigger.destination_scene="res://tests/nonexistent_portal.tscn"
   trigger._on_body_entered(player)
   assert(player.input_enabled and not trigger.transferring and not zone.has_meta("portal_load_pending"))
   trigger.destination_scene=original
   print("INVALID_DESTINATION_RECOVERY PASS")
  var old=weakref(zone)
  var old_player=weakref(player)
  var start=Time.get_ticks_msec()
  trigger._on_body_entered(player)
  assert(trigger.transferring and not player.input_enabled and zone.get_meta("portal_load_pending"))
  assert(zone.get_node("ZoneUIBinding")._travel_or_combat_busy())
  trigger._on_body_entered(player)
  await scene_changed
  for f in range(5): await physics_frame
  assert(current_scene.name==route[i+1] and old.get_ref()==null and old_player.get_ref()==null)
  assert(current_scene.checkpoint_player.input_enabled and not current_scene.has_meta("portal_load_pending"))
  print("THREADED_PORTAL ",route[i]," -> ",route[i+1]," ms=",Time.get_ticks_msec()-start)
 current_scene.queue_free()
 for i in range(3): await process_frame
 root.get_node("AudioDirector").stop_all_audio_immediately()
 await create_timer(0.35).timeout
 print("ALL_PORTALS PASS")
 quit(0)
