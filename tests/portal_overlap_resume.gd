extends SceneTree
func _initialize():call_deferred("_run")
func frames(n:int):
 for i in range(n):await physics_frame
func _run():
 if OS.get_environment("REVERIE_E2E_DISABLE_LOCAL_SAVE")!="1":
  quit(2)
  return
 var gs=root.get_node("GameState")
 gs.quest_domain.flags["tutorial_complete"]=true
 gs.quest_domain.flags["village_gerald_defeated"]=true
 change_scene_to_file("res://scenes/world/six_zone_reverie/individual_zones/zone_02_royal_gate_standalone.tscn")
 await scene_changed
 await frames(8)
 var z=current_scene
 var p=z.checkpoint_player
 var exit=z.get_node("TransferPoints/ToPreviousZone/ToPreviousZoneTrigger")
 var origin=p.global_position
 p.input_enabled=false
 p.global_position=exit.global_position
 await frames(8)
 assert(exit.get_overlapping_bodies().has(p))
 assert(not exit.transferring and exit.is_physics_processing())
 p.global_position=origin
 await frames(8)
 p.input_enabled=true
 await frames(8)
 assert(current_scene==z and not exit.transferring and not exit.is_physics_processing())
 print("LEAVING BLOCKED PORTAL CANCELS PENDING TRAVEL PASS")
 z.set_meta("cassien_ritual_active",true)
 p.global_position=exit.global_position
 await frames(8)
 assert(not exit.transferring and exit.is_physics_processing())
 p.input_enabled=false
 z.remove_meta("cassien_ritual_active")
 await frames(8)
 assert(not exit.transferring)
 p.input_enabled=true
 for i in range(300):
  await physics_frame
  if current_scene!=z:break
 assert(current_scene!=null and current_scene.name==&"StandaloneZone01")
 await frames(20)
 assert(current_scene.name==&"StandaloneZone01" and current_scene.checkpoint_player.input_enabled)
 print("MODAL LOCK, INPUT RESTORE, REAL OVERLAP TRANSFER, NO BOUNCE PASS")
 current_scene.queue_free()
 for i in range(3):await process_frame
 root.get_node("AudioDirector").stop_all_audio_immediately()
 await create_timer(.35).timeout
 quit()
