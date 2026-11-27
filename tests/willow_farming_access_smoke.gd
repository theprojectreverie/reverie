extends SceneTree
func _initialize():call_deferred("_run")
func _run():
 if OS.get_environment("REVERIE_E2E_DISABLE_LOCAL_SAVE")!="1":
  quit(2)
  return
 var gs=root.get_node("GameState")
 gs.quest_domain.flags["tutorial_complete"]=true
 change_scene_to_file("res://scenes/world/six_zone_reverie/individual_zones/zone_03_willow_fields_standalone.tscn")
 await scene_changed
 for i in range(5):await physics_frame
 var z=current_scene
 var l=z.get_node("Zone/GroundTiles/EditableTileMap")
 var q=PhysicsShapeQueryParameters2D.new()
 q.shape=z.checkpoint_player.get_node("CollisionShape2D").shape
 q.collision_mask=1
 var space=z.get_world_2d().direct_space_state
 var available={}
 for c in l.get_used_cells():
  if l.get_cell_source_id(c)==1:continue
  var p=l.to_global(l.map_to_local(c))
  q.transform=Transform2D(0,p+Vector2(0,-10))
  if space.intersect_shape(q,1).is_empty():available[c]=true
 var targets=[Vector2(-2540,1450),Vector2(-2204,1716),Vector2(-640,730),Vector2(-2318,1569),Vector2(-560,2448),Vector2(900,1700),Vector2(1440,1430),Vector2(1710,1300),Vector2(1770,1157),Vector2(2900,1722),Vector2(-1520,1610),Vector2(-1230,1510),Vector2(-1410,1750),Vector2(-270,720),Vector2(-110,2110),Vector2(-1110,1910),Vector2(-240,1550),Vector2(510,925),Vector2(-1590,1582),Vector2(-1270,1492),Vector2(-1450,1710),Vector2(-300,727),Vector2(-170,2075),Vector2(-1160,1890),Vector2(-260,1545),Vector2(470,850)]
 var start=Vector2i.ZERO
 var near=INF
 for c in available:
  var d=l.to_global(l.map_to_local(c)).distance_to(targets[0])
  if d<near:
   near=d
   start=c
 assert(near<100)
 var visited={start:true}
 var queue:Array[Vector2i]=[start]
 var idx=0
 while idx<queue.size():
  var c=queue[idx]
  idx+=1
  for n in l.get_surrounding_cells(c):
   if not available.has(n) or visited.has(n):continue
   var a=l.to_global(l.map_to_local(c))
   var b=l.to_global(l.map_to_local(n))
   var clear=true
   for t in [0.25,0.5,0.75]:
    q.transform=Transform2D(0,a.lerp(b,t)+Vector2(0,-10))
    if not space.intersect_shape(q,1).is_empty():
     clear=false
     break
   if clear:
    visited[n]=true
    queue.append(n)
 var errs=[]
 for p in targets:
  near=INF
  for c in visited:
   near=minf(near,l.to_global(l.map_to_local(c)).distance_to(p))
  print("ROAD ACCESS ",p," distance ",near)
  if near>80:errs.append(p)
 print("CONNECTED ROAD CELLS ",visited.size(),"/",available.size()," ERRORS ",errs)
 z.queue_free()
 for i in range(3):await process_frame
 root.get_node("AudioDirector").stop_all_audio_immediately()
 await create_timer(0.35).timeout
 quit(0 if errs.is_empty() else 1)


