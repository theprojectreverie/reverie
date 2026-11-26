extends SceneTree
func _initialize():call_deferred("_run")
func _run():
 if OS.get_environment("REVERIE_E2E_DISABLE_LOCAL_SAVE")!="1":
  quit(2)
  return
 var cp=load("res://scripts/world/six_zone_reverie/six_zone_checkpoint.gd")
 var gs=root.get_node("GameState")
 var touch=root.get_node("TouchInput")
 gs.quest_domain.flags["tutorial_complete"]=true
 var errors=[]
 var attempts=0
 var scenes=cp.SCENES.duplicate()
 scenes["TrainingGroundV02"]="res://scenes/world/tutorial_prologue/training_ground_v02.tscn"
 for id in scenes:
  gs.quest_domain.flags["six_zone_checkpoint"]={"zone":id,"x":20000,"y":20000}
  change_scene_to_file(scenes[id])
  await scene_changed
  for j in range(5):await physics_frame
  var z=current_scene
  var p=z.get_node("Kael") if id=="TrainingGroundV02" else z.checkpoint_player
  var poly=PackedVector2Array()
  if id=="StandaloneZone01":
   for e in z.get_node("GroundPerimeter").get_children():
    if e is CollisionShape2D:poly.append(e.to_global(e.shape.a))
  elif id=="StandaloneVillage":
   poly=z.get_node("Perimeter/Bounds").polygon
  elif id=="TrainingGroundV02":
   poly=z.get_node("Boundaries/OuterSafetyOutline").polygon
  else:
   poly=z.get_node("TerrainPerimeter/TerrainOutline").polygon
  if not Geometry2D.is_point_in_polygon(p.global_position,poly):errors.append([id,"spawn",p.global_position])
  if id!="TrainingGroundV02" and cp.safe_position(z,Vector2(20000,20000)):errors.append([id,"bad checkpoint accepted"])
  var transfers=z.get_node_or_null("TransferPoints")
  if transfers:
   for m in transfers.get_children():
    for c in m.get_children():
     if c is Area2D:c.monitoring=false
  var combat=p.get_node("WorldCombatComponent")
  for i in range(poly.size()):
   var a=poly[i]
   var b=poly[(i+1)%poly.size()]
   var mid=(a+b)*0.5
   var n=(b-a).orthogonal().normalized()
   if not Geometry2D.is_point_in_polygon(mid+n*24,poly):n=-n
   p.global_position=mid+n*24+Vector2(0,5)
   p.velocity=Vector2.ZERO
   p.input_enabled=true
   combat.dodge_recovery=0
   combat.dodge_time=0
   touch.set_move_vector(-n)
   await physics_frame
   if not combat.try_dodge():errors.append([id,"dodge not started",i])
   for j in range(22):await physics_frame
   if not Geometry2D.is_point_in_polygon(p.global_position,poly):errors.append([id,"escaped",i,p.global_position])
   touch.release()
   attempts+=1
  print(id," dodge edges ",poly.size()," errors ",errors.size())
  root.get_node("AudioDirector").stop_all_audio_immediately()
  await create_timer(.1).timeout
 print("DODGE PERIMETER ",attempts," FAILURES ",errors)
 current_scene.queue_free()
 for j in range(4):await process_frame
 root.get_node("AudioDirector").stop_all_audio_immediately()
 await create_timer(.35).timeout
 quit(0 if errors.is_empty() else 1)
