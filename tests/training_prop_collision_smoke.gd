extends SceneTree
func _initialize():
 call_deferred("run")
func run():
 var scene=load("res://scenes/world/tutorial_prologue/training_ground_v02.tscn").instantiate()
 root.add_child(scene)
 await physics_frame
 await physics_frame
 var names=["BarrelsAndSack","HangingTrainingDummy","SpearStand","WoodenPostDummy","CrystalShrine","CrystalSupplyTable","StoneBrazier","StoneBrazier2"]
 var world=scene.get_world_2d().direct_space_state
 for n in names:
  var poly=scene.get_node("Boundaries/"+n+"Footprint")
  var parts=Geometry2D.triangulate_polygon(poly.polygon)
  if parts.is_empty():
   push_error("Invalid polygon: "+n);quit(1);return
  var center=(poly.polygon[parts[0]]+poly.polygon[parts[1]]+poly.polygon[parts[2]])/3.0
  var query=PhysicsPointQueryParameters2D.new()
  query.position=poly.to_global(center)
  query.collision_mask=1
  if world.intersect_point(query).is_empty():
   push_error("No physics collision: "+n);quit(1);return
  print("PASS footprint ",n)
 for p in [Vector2(0,200),Vector2(0,100),Vector2(0,0),Vector2(0,-30),Vector2(250,25)]:
  var query=PhysicsPointQueryParameters2D.new()
  query.position=p
  query.collision_mask=1
  if not world.intersect_point(query).is_empty():
   push_error("Blocked route "+str(p));quit(1);return
 var prop=scene.get_node("TutorialProps/HangingTrainingDummy")
 var original=prop.global_position
 scene.dummy.play_heavy_hit()
 await create_timer(.1).timeout
 if prop.global_position!=original:
  push_error("Prop moves on hit");quit(1);return
 print("PASS central path clear; unrelated props stay stationary on dummy hit")
 scene.queue_free()
 for i in range(3):await process_frame
 quit(0)