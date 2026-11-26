extends SceneTree
var CHECKPOINT
func _initialize():call_deferred("_run")
func _run():
 if OS.get_environment("REVERIE_E2E_DISABLE_LOCAL_SAVE")!="1":
  quit(2)
  return
 CHECKPOINT=load("res://scripts/world/six_zone_reverie/six_zone_checkpoint.gd")
 var gs=root.get_node("GameState")
 gs.quest_domain.flags["tutorial_complete"]=true
 var failures=[]
 var count=0
 for zone_number in range(2,7):
  var name_id="StandaloneZone0"+str(zone_number)
  gs.quest_domain.flags["six_zone_checkpoint"]={"zone":name_id,"x":20000,"y":20000}
  change_scene_to_file(CHECKPOINT.SCENES[name_id])
  await scene_changed
  for i in range(5):await physics_frame
  var z=current_scene
  var p=z.checkpoint_player
  var perimeter=z.get_node("TerrainPerimeter")
  var poly=perimeter.get_node("TerrainOutline").polygon
  var space=z.get_world_2d().direct_space_state
  var initial=p.global_position
  if not Geometry2D.is_point_in_polygon(initial,poly):
   failures.append([name_id,"bad spawn",initial])
  if CHECKPOINT.safe_position(z,Vector2(20000,20000)):
   failures.append([name_id,"unsafe checkpoint accepted"])
  for m in z.get_node("TransferPoints").get_children():
   if not m is Marker2D:continue
   if not Geometry2D.is_point_in_polygon(m.position,poly):
    failures.append([name_id,"marker outside",m.name,m.position])
   for child in m.get_children():
    if child is Area2D:child.monitoring=false
  p.input_enabled=false
  p.locomotion_component.set_physics_process(false)
  for i in range(poly.size()):
   var a=poly[i]
   var b=poly[(i+1)%poly.size()]
   var mid=(a+b)*0.5
   var n=(b-a).orthogonal().normalized()
   if not Geometry2D.is_point_in_polygon(mid+n*32,poly):n=-n
   for t in [0.2,0.5,0.8]:
    var edge=a.lerp(b,t)
    var from=edge+n*25
    var to=edge-n*25
    var ray=PhysicsRayQueryParameters2D.create(from,to,1)
    ray.exclude=[p.get_rid()]
    var hit=space.intersect_ray(ray)
    if hit.is_empty() or hit.collider!=perimeter:
     # Other terrain props can overlap a boundary, so also test specifically with a capsule sweep.
     if hit.is_empty():failures.append([name_id,"open boundary",edge])
    count+=1
   p.global_position=mid+n*36+Vector2(0,10)
   await physics_frame
   var hit=p.move_and_collide(-n*100)
   if hit==null or not Geometry2D.is_point_in_polygon(p.global_position,poly):
    failures.append([name_id,"player escaped",mid,p.global_position])
  p.global_position=initial
  print(name_id," ",poly.size()," edges; restored spawn ",initial," failures ",failures.size())
  root.get_node("AudioDirector").stop_all_audio_immediately()
  await create_timer(.15).timeout
 print("PERIMETER CHECKS ",count," FAILURES ",failures)
 current_scene.queue_free()
 for i in range(3):await process_frame
 root.get_node("AudioDirector").stop_all_audio_immediately()
 await create_timer(.35).timeout
 quit(0 if failures.is_empty() else 1)
