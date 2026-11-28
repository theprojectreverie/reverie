extends SceneTree
var zone:Node2D
var player:CharacterBody2D
var ground:TileMapLayer
var nav:=AStarGrid2D.new()
var q:=PhysicsShapeQueryParameters2D.new()
var distance:=0.0
func _initialize():call_deferred("_run")
func clear(p:Vector2)->bool:
 if ground.get_cell_source_id(ground.local_to_map(ground.to_local(p)))<0:return false
 q.transform=Transform2D(0,p+Vector2(0,-10))
 q.motion=Vector2.ZERO
 return zone.get_world_2d().direct_space_state.intersect_shape(q,1).is_empty()
func build():
 nav.region=Rect2i(-80,-4,162,88)
 nav.cell_size=Vector2(40,40)
 nav.diagonal_mode=AStarGrid2D.DIAGONAL_MODE_ONLY_IF_NO_OBSTACLES
 nav.update()
 for y in range(-4,84):
  for x in range(-80,82):
   var c=Vector2i(x,y)
   nav.set_point_solid(c,not clear(Vector2(c)*40))
func nearest(p:Vector2)->Vector2i:
 var c=Vector2i((p/40).round())
 var best=c
 var d=INF
 for i in range(-4,5):
  for j in range(-4,5):
   var k=c+Vector2i(i,j)
   if nav.is_in_boundsv(k) and not nav.is_point_solid(k):
    var l=p.distance_to(Vector2(k)*40)
    if l<d:d=l;best=k
 return best
func segment(a:Vector2,b:Vector2)->bool:
 q.transform=Transform2D(0,a+Vector2(0,-10))
 q.motion=b-a
 var r=zone.get_world_2d().direct_space_state.cast_motion(q)
 q.motion=Vector2.ZERO
 return r.size()==2 and r[0]>.999
func walk(target:Vector2)->bool:
 var path=nav.get_point_path(nearest(player.global_position),nearest(target))
 if path.is_empty():return false
 var origin=player.global_position
 var pts:Array[Vector2]=[]
 var k=0
 while k<path.size():
  var far=k
  while far+1<path.size() and segment(origin,path[far+1]):far+=1
  pts.append(path[far]);origin=path[far];k=far+1
 if clear(target) and segment(origin,target):pts.append(target)
 var touch=root.get_node("TouchInput")
 for p in pts:
  var attempts=0
  while player.global_position.distance_to(p)>12 and attempts<400:
   if not is_instance_valid(zone) or current_scene!=zone or zone.get_meta("portal_load_pending",false):
    touch.set_move_vector(Vector2.ZERO)
    return true
   var old=player.global_position
   touch.set_move_vector((p-old).normalized()*clampf((p-old).length()/70,.45,1))
   await physics_frame
   distance+=old.distance_to(player.global_position)
   attempts+=1
  if player.global_position.distance_to(p)>12:
   touch.set_move_vector(Vector2.ZERO)
   print("WALK BLOCKED ",p," at ",player.global_position)
   return false
 touch.set_move_vector(Vector2.ZERO)
 return player.global_position.distance_to(target)<50
func _run():
 if OS.get_environment("REVERIE_E2E_DISABLE_LOCAL_SAVE")!="1":quit(2);return
 var gs=root.get_node("GameState")
 gs.quest_domain.flags["tutorial_complete"]=true
 gs.quest_domain.flags["six_zone_checkpoint"]={"zone":"StandaloneZone04","x":-1600.0,"y":1050.0}
 change_scene_to_file("res://scenes/world/six_zone_reverie/individual_zones/zone_04_elderwood_grove_standalone.tscn")
 await scene_changed
 for i in range(8):await physics_frame
 zone=current_scene
 player=zone.checkpoint_player
 ground=zone.get_node("Zone/GroundTiles/EditableTileMap")
 q.shape=player.get_node("CollisionShape2D").shape
 q.collision_mask=1
 q.exclude=[player.get_rid()]
 build()
 var a=zone.get_node("ElderwoodRelics/BrokenMemorial")
 var b=zone.get_node("ElderwoodRelics/WeatheredPillar")
 var shrine=zone.get_node("Zone/DrownedOrchidRuins/OrchidSoulEncounter")
 var entry=zone.get_node("Zone/DrownedOrchidRuins/Entrance")
 var targets=[a.global_position+Vector2(0,60),entry.global_position,shrine.global_position,entry.global_position,b.global_position+Vector2(0,60),Vector2(1568,2352)]
 print("START ",player.global_position)
 for i in range(targets.size()):
  if not await walk(targets[i]):print("ROUTE FAILED ",i);quit(1);return
  if i==5:
   var deadline=Time.get_ticks_msec()+30000
   while Time.get_ticks_msec()<deadline:
    if current_scene!=null and current_scene.name==&"StandaloneZone05":break
    await process_frame
   if current_scene==null or current_scene.name!=&"StandaloneZone05":print("EXIT TRANSITION FAILED");quit(1);return
   print("ACTUAL ZONE 5 TRANSITION PASS")
   break
  print("WALKED ",i," ",player.global_position)
  if i==0:a.interact()
  if i==4:b.interact()
 print("WALKED ENTIRE QUEST ROUTE distance=",distance," quest=",gs.quest_domain.quest_state("elderwood_relics"))
 if gs.quest_domain.quest_state("elderwood_relics")!="complete":quit(1);return
 if is_instance_valid(current_scene):current_scene.queue_free()
 for i in range(3):await process_frame
 root.get_node("AudioDirector").stop_all_audio_immediately()
 await create_timer(.35).timeout
 quit(0)
