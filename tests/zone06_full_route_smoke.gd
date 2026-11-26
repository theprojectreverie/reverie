extends SceneTree
func _initialize():call_deferred("_run")
func _run():
 if OS.get_environment("REVERIE_E2E_DISABLE_LOCAL_SAVE")!="1":quit(2);return
 var gs=root.get_node("GameState")
 gs.quest_domain.flags["tutorial_complete"]=true
 gs.quest_domain.flags["ravienna_resurrected"]=true
 change_scene_to_file("res://scenes/world/six_zone_reverie/individual_zones/zone_06_ruined_tower_standalone.tscn")
 await scene_changed
 for i in range(8):await physics_frame
 var z=current_scene
 var p=z.checkpoint_player
 p.input_enabled=false
 var failures=[]
 for side in [-1,1]:
  var route=[Vector2(0,2460),Vector2(300*side,2200),Vector2(300*side,1750),Vector2(0,1530),Vector2(0,1180),Vector2(800*side,1180),Vector2(800*side,1050),Vector2(1100*side,1050)]
  for i in range(route.size()-1):
   p.global_position=route[i]
   await physics_frame
   var blocked=p.test_move(p.global_transform,route[i+1]-route[i])
   print("ROUTE ",side," ",route[i]," -> ",route[i+1]," clear=",not blocked)
   if blocked:failures.append([side,i])
 var guard=z.get_node("PalaceStairElevation/TerraceEdgeGuards")
 var space=p.get_world_2d().direct_space_state
 var outline=z.get_node("PalaceStairElevation").upper_outline
 var checks=0
 for i in range(outline.size()):
  if i==6:continue
  var a=outline[i]
  var b=outline[(i+1)%outline.size()]
  var normal=(b-a).orthogonal().normalized()
  if not Geometry2D.is_point_in_polygon((a+b)*0.5+normal*20,outline):normal=-normal
  for j in range(1,10):
   var edge=a.lerp(b,j/10.0)
   var hit=space.intersect_ray(PhysicsRayQueryParameters2D.create(edge+normal*35,edge-normal*35,1))
   checks+=1
   if hit.is_empty():failures.append(["terrace edge",i,j])
 print("TERRACE GUARDS ",checks," FAILURES ",failures)
 var arch=z.get_node("Zone/GothicArchitecture")
 var props=0
 for prop in arch.get_children():
  if prop is StaticBody2D and not str(prop.name).begins_with("Edge"):
   var found=false
   for c in prop.get_children():
    if c is CollisionPolygon2D and not c.disabled:
     found=true
   if not found:failures.append(["missing footprint",prop.name])
   props+=1
 print("DECORATION FOOTPRINTS ",props," FAILURES ",failures)
 current_scene.queue_free()
 for i in range(10):await process_frame
 root.get_node("AudioDirector").stop_all_audio_immediately()
 await create_timer(0.5).timeout
 quit(0 if failures.is_empty() else 1)
