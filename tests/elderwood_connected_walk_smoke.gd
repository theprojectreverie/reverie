extends SceneTree
var navigation:AStarGrid2D
var travel_distance:=0.0
func _initialize():call_deferred("_run")
func _run():
 if OS.get_environment("REVERIE_E2E_DISABLE_LOCAL_SAVE")!="1":quit(2);return
 var gs=root.get_node("GameState")
 gs.quest_domain.flags["tutorial_complete"]=true
 gs.quest_domain.flags["discovered_fast_travel_zones"]=["StandaloneVillage","StandaloneZone01","StandaloneZone02","StandaloneZone03"]
 gs.quest_domain.flags["six_zone_checkpoint"]={"zone":"StandaloneZone04","x":-1600.0,"y":1050.0}
 change_scene_to_file("res://scenes/world/six_zone_reverie/individual_zones/zone_04_elderwood_grove_standalone.tscn")
 await scene_changed
 for i in range(8):await physics_frame
 var z=current_scene
 var player=z.checkpoint_player
 var exit=z.get_node("TransferPoints/ToNextZone/ToNextZoneTrigger")
 var prev=z.get_node("TransferPoints/ToPreviousZone/ToPreviousZoneTrigger")
 exit.monitoring=false
 exit.set_physics_process(false)
 prev.monitoring=false
 prev.set_physics_process(false)
 var a=z.get_node("ElderwoodRelics/BrokenMemorial")
 var b=z.get_node("ElderwoodRelics/WeatheredPillar")
 var shrine=z.get_node("Zone/DrownedOrchidRuins/OrchidSoulEncounter")
 var points=[a.global_position+Vector2(0,60),b.global_position+Vector2(0,60),shrine.global_position,Vector2(1568,2352)]
 var errors=[]
 player.global_position=Vector2(-1600,1050)
 player.reset_physics_interpolation()
 await physics_frame
 build_navigation(z)
 for i in range(points.size()):
  var ok=await walk_to(player,points[i])
  print("ELDERWOOD WALK target=",i," result=",ok," pos=",player.global_position," requested=",points[i])
  if not ok:errors.append(i);break
  if i==0:a.interact()
  if i==1:b.interact()
 print("ELDERWOOD CONNECTED WALK distance=",travel_distance," errors=",errors," quest=",gs.quest_domain.quest_state("elderwood_relics"))
 var passed=errors.is_empty() and gs.quest_domain.quest_state("elderwood_relics")=="complete"
 z.queue_free()
 for i in range(3):await process_frame
 root.get_node("AudioDirector").stop_all_audio_immediately()
 await create_timer(.35).timeout
 quit(0 if passed else 1)

func build_navigation(zone:Node2D):
 navigation=AStarGrid2D.new()
 navigation.region=Rect2i(-81,-4,165,87)
 navigation.cell_size=Vector2(40,40)
 navigation.diagonal_mode=AStarGrid2D.DIAGONAL_MODE_ONLY_IF_NO_OBSTACLES
 navigation.update()
 var ground=zone.get_node("Zone/GroundTiles/EditableTileMap")
 var space=zone.get_world_2d().direct_space_state
 var shape=CircleShape2D.new()
 shape.radius=18
 var q=PhysicsShapeQueryParameters2D.new()
 q.shape=shape
 q.collision_mask=1
 for y in range(navigation.region.position.y,navigation.region.end.y):
  for x in range(navigation.region.position.x,navigation.region.end.x):
   var id=Vector2i(x,y)
   q.transform=Transform2D(0,Vector2(id)*40.0)
   if ground.get_cell_source_id(ground.local_to_map(ground.to_local(Vector2(id)*40.0)))<0 or not space.intersect_shape(q,1).is_empty():navigation.set_point_solid(id)
func near_grid(pos:Vector2)->Vector2i:
 var center=Vector2i((pos/40.0).round())
 var best=center
 var dist=INF
 for x in range(center.x-3,center.x+4):
  for y in range(center.y-3,center.y+4):
   var id=Vector2i(x,y)
   if not navigation.is_in_boundsv(id) or navigation.is_point_solid(id):continue
   var d=pos.distance_to(Vector2(id)*40.0)
   if d<dist:dist=d;best=id
 return best
func clear_segment(space:PhysicsDirectSpaceState2D,a:Vector2,b:Vector2)->bool:
 var shape=CircleShape2D.new()
 shape.radius=18
 var q=PhysicsShapeQueryParameters2D.new()
 q.shape=shape
 q.collision_mask=1
 q.transform=Transform2D(0,a)
 q.motion=b-a
 var f=space.cast_motion(q)
 return f.size()>=2 and f[0]>0.99
func walk_to(player:CharacterBody2D,target:Vector2)->bool:
 var path=navigation.get_point_path(near_grid(player.global_position),near_grid(target))
 if path.is_empty():return false
 var points:Array[Vector2]=[]
 var space=player.get_world_2d().direct_space_state
 var origin=player.global_position
 var k=0
 while k<path.size():
  var j=k
  for n in range(k,path.size()):
   if clear_segment(space,origin,path[n]):j=n
   else:break
  points.append(path[j])
  origin=path[j]
  k=j+1
 if clear_segment(space,origin,target):points.append(target)
 var touch=root.get_node("TouchInput")
 for point in points:
  var frames=0
  while player.global_position.distance_to(point)>12 and frames<1000:
   frames+=1
   var delta=point-player.global_position
   var old=player.global_position
   touch.set_move_vector(delta.normalized()*clampf(delta.length()/70.0,0.45,1.0))
   await physics_frame
   travel_distance+=old.distance_to(player.global_position)
  touch.release()
  if player.global_position.distance_to(point)>18:return false
 await create_timer(0.15).timeout
 return player.global_position.distance_to(target)<35
