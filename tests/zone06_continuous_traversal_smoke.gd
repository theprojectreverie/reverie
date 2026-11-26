extends SceneTree
func _initialize():call_deferred("_run")
func _walk(p:CharacterBody2D,destination:Vector2)->bool:
 var touch=root.get_node("TouchInput")
 for i in range(1200):
  var delta=destination-p.global_position
  if delta.length()<19.0:
   touch.release()
   for j in range(12):await physics_frame
   return p.global_position.distance_to(destination)<28.0
  touch.set_move_vector(delta.normalized()*0.8)
  await physics_frame
 touch.release()
 return false

func _run():
 if OS.get_environment("REVERIE_E2E_DISABLE_LOCAL_SAVE")!="1":quit(2);return
 var gs=root.get_node("GameState")
 gs.quest_domain.flags["tutorial_complete"]=true
 gs.quest_domain.flags["ravienna_resurrected"]=true
 change_scene_to_file("res://scenes/world/six_zone_reverie/individual_zones/zone_06_ruined_tower_standalone.tscn")
 await scene_changed
 for i in range(12):await physics_frame
 var z=current_scene
 var p=z.checkpoint_player
 p.global_position=z.get_node("TransferPoints/SafeSpawnFromPreviousZone").global_position
 p.velocity=Vector2.ZERO
 var route=[Vector2(-300,2200),Vector2(-300,1750),Vector2(0,1530),Vector2(0,1180),Vector2(-800,1180),Vector2(-800,1050),Vector2(-1100,1050),Vector2(-800,1050),Vector2(-800,1180),Vector2(0,1180),Vector2(0,1115),Vector2(0,1180),Vector2(800,1180),Vector2(800,1050),Vector2(1100,1050),Vector2(800,1050),Vector2(800,1180),Vector2(0,1180),Vector2(0,1530),Vector2(300,1750),Vector2(300,2200),Vector2(0,2460)]
 var checked=0
 for pt in route:
  var reached=await _walk(p,pt)
  print("LIVE ROUTE ",pt," actual=",p.global_position," height=",p.get_meta("surface_elevation",0)," reached=",reached)
  if not reached:quit(1);return
  if pt.y<=1180 and float(p.get_meta("surface_elevation",0))<110.0:quit(1);return
  if pt.y>=1530 and not is_zero_approx(float(p.get_meta("surface_elevation",0))):quit(1);return
  if pt==Vector2(0,1115):
   var interaction=p.get_node("InteractionComponent")
   interaction.refresh_nearest()
   if interaction.get_current()!=z.get_node("ReviennaEncounter"):quit(1);return
   interaction.try_interact()
   var dialog=z.get_node("UI/Dialogue")
   if not dialog.visible:quit(1);return
   dialog.close()
   await physics_frame
  checked+=1
 print("CONTINUOUS WALK WITHOUT TELEPORTS PASS ",checked," waypoints")
 current_scene.queue_free()
 for i in range(12):await process_frame
 root.get_node("AudioDirector").stop_all_audio_immediately()
 await create_timer(1.0).timeout
 quit(0)
