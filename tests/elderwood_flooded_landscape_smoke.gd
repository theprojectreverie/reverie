extends SceneTree
func _initialize(): call_deferred("_run")
func _run():
 if OS.get_environment("REVERIE_E2E_DISABLE_LOCAL_SAVE")!="1":
  quit(2)
  return
 root.get_node("GameState").quest_domain.flags["tutorial_complete"]=true
 change_scene_to_file("res://scenes/world/six_zone_reverie/individual_zones/zone_04_elderwood_grove_standalone.tscn")
 await scene_changed
 for i in range(8): await physics_frame
 var z=current_scene
 var q=PhysicsShapeQueryParameters2D.new()
 q.shape=z.checkpoint_player.get_node("CollisionShape2D").shape
 q.collision_mask=1
 var space=z.get_world_2d().direct_space_state
 var routes=[[Vector2(-1600,1050),Vector2(-1168,1266),Vector2(-700,1430),Vector2(-350,1545),Vector2(-176,1710),Vector2(440,2018),Vector2(760,2050),Vector2(1200,2200),Vector2(1568,2352)],[Vector2(-350,1545),Vector2(40,1350),Vector2(320,1210),Vector2(525,1216)]]
 var errors=[]
 var water=z.get_node("Zone/FloodedLandscape/OpenWaterCollision")
 var total_water=water.get_used_cells().size()
 if total_water<5000:errors.append("water coverage below half: "+str(total_water))
 for pos in [Vector2(0,160),Vector2(-1200,1600),Vector2(1100,2200),Vector2(300,2940)]:
  var cell=water.local_to_map(water.to_local(pos))
  if water.get_cell_source_id(cell)>=0:
   q.transform=Transform2D(0,water.to_global(water.map_to_local(cell)))
   if not space.intersect_shape(q,16).any(func(h):return h.collider==water):errors.append("open water collision missing "+str(pos))
 print("OPEN WATER CELLS ",total_water)
 var samples=0
 for route in routes:
  for i in range(route.size()-1):
   var a=route[i];var b=route[i+1];var n=maxi(1,ceili(a.distance_to(b)/10))
   for j in range(n+1):
    var pos=a.lerp(b,float(j)/n)
    q.transform=Transform2D(0,pos+Vector2(0,-10))
    if not space.intersect_shape(q,1).is_empty(): errors.append(pos)
    samples+=1
 for pos in [Vector2(-280,620),Vector2(-1800,1670),Vector2(2100,1530),Vector2(-150,2460)]:
  q.transform=Transform2D(0,pos)
  if space.intersect_shape(q,1).is_empty():errors.append("water not blocked "+str(pos))
 print("FLOODED LANDSCAPE ROUTE samples=",samples," errors=",errors.size()," ",errors.slice(0,30))
 z.queue_free()
 for i in range(3):await process_frame
 root.get_node("AudioDirector").stop_all_audio_immediately()
 await create_timer(.35).timeout
 quit(0 if errors.is_empty() else 1)
