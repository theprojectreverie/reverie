extends SceneTree
var zone:Node2D
var player:CharacterBody2D
var ground:TileMapLayer
var q=PhysicsShapeQueryParameters2D.new()
var reachable:Dictionary={}
const GRID=32
const WATER_NAMES=["NorthernMirrorCollision","WestFloodplainCollision","EasternLakeCollision","SouthernLagoonCollision","OpenWaterCollision"]
func _initialize():call_deferred("_run")
func anchor(n:Node2D)->Node2D:
 var chain:Array[Node2D]=[]
 var p:Node=n
 while p!=zone and p is Node2D:
  chain.push_front(p)
  p=p.get_parent()
 for x in chain:
  if not x.y_sort_enabled:return x
 return n
func clear(p:Vector2)->bool:
 if ground.get_cell_source_id(ground.local_to_map(ground.to_local(p)))<0:return false
 q.transform=Transform2D(0,p+Vector2(0,-10))
 return root.world_2d.direct_space_state.intersect_shape(q,1).is_empty()
func build_reachable():
 var pending:Array[Vector2i]=[Vector2i((Vector2(-1600,1050)/GRID).round())]
 reachable[pending[0]]=true
 var checked:Dictionary={}
 var index=0
 while index<pending.size():
  var a=pending[index];index+=1
  for d in [Vector2i.UP,Vector2i.DOWN,Vector2i.LEFT,Vector2i.RIGHT]:
   var b=a+d
   if checked.has(b) or reachable.has(b):continue
   checked[b]=true
   var start=Vector2(a)*GRID
   var finish=Vector2(b)*GRID
   if not clear(finish):continue
   var ok=true
   for i in [0.25,0.5,0.75]:
    if not clear(start.lerp(finish,i)):ok=false;break
   if ok:reachable[b]=true;pending.append(b)
 print("CONNECTED DRY GRID ",reachable.size())
func nearby_reachable(p:Vector2,radius:int)->bool:
 var c=Vector2i((p/GRID).round())
 for x in range(-radius,radius+1):
  for y in range(-radius,radius+1):
   if reachable.has(c+Vector2i(x,y)):return true
 return false
func short_side_walk(center:Vector2)->bool:
 for r in [24,48,72,96,120,160,200]:
  for d in [Vector2.UP,Vector2.DOWN,Vector2.LEFT,Vector2.RIGHT]:
   var a=center+d*r
   if not nearby_reachable(a,1):continue
   var b=a+d.orthogonal()*32
   var ok=true
   for k in range(9):
    if not clear(a.lerp(b,float(k)/8)):ok=false;break
   if not ok:continue
   place(a)
   await physics_frame
   var touch=root.get_node("TouchInput")
   var count=0
   while player.global_position.distance_to(b)>9 and count<60:
    touch.set_move_vector((b-player.global_position).normalized());await physics_frame;count+=1
   touch.set_move_vector(Vector2.ZERO)
   if player.global_position.distance_to(b)>9:continue
   count=0
   while player.global_position.distance_to(a)>9 and count<60:
    touch.set_move_vector((a-player.global_position).normalized());await physics_frame;count+=1
   touch.set_move_vector(Vector2.ZERO)
   if player.global_position.distance_to(a)<=9:return true
 return false
func corridor(center:Vector2)->Variant:
 for distance in range(12,301,12):
  for sign_x in [-1,1]:
   var p=center+Vector2(distance*sign_x,-30)
   var ok=true
   for y in range(0,77,4):
    if not clear(p+Vector2(0,y)):
     ok=false
     break
   if ok:return p
 return null
func place(p:Vector2)->void:
 player.global_position=p
 player.velocity=Vector2.ZERO
 player.reset_physics_interpolation()
func drive(action:String,threshold:float,down:bool)->bool:
 Input.action_press(action)
 var success=false
 for i in range(100):
  await physics_frame
  if (player.global_position.y>=threshold if down else player.global_position.y<=threshold):
   success=true
   break
 Input.action_release(action)
 player.velocity=Vector2.ZERO
 return success
func approach_boundary(a:Node2D)->bool:
 var bodies=a.find_children("*","StaticBody2D",true,false)
 if a is StaticBody2D:bodies.push_front(a)
 if bodies.is_empty():return false
 var center=a.global_position
 for body in bodies:
  var polys=body.find_children("*","CollisionPolygon2D",true,false)
  for poly in polys:
   var avg=Vector2.ZERO
   for v in poly.polygon:avg+=poly.to_global(v)
   center=avg/poly.polygon.size()+Vector2(0,10)
   for d in [Vector2.UP,Vector2.DOWN,Vector2.LEFT,Vector2.RIGHT,Vector2(-1,-1).normalized(),Vector2(1,-1).normalized(),Vector2(-1,1).normalized(),Vector2(1,1).normalized()]:
    for distance in [36,48,64,80,100,128,160]:
     var start=center-d*distance
     if not clear(start):continue
     var hit=false
     for k in range(4,distance+4,4):
      var p=start+d*k
      if ground.get_cell_source_id(ground.local_to_map(ground.to_local(p)))<0:break
      q.transform=Transform2D(0,p+Vector2(0,-10))
      var hits=root.world_2d.direct_space_state.intersect_shape(q,16)
      if not hits.is_empty():
       hit=hits.any(func(h):return h.collider==body)
       break
     if not hit:continue
     place(start)
     await physics_frame
     var actions=[]
     if d.x<-.1:actions.append("move_left")
     if d.x>.1:actions.append("move_right")
     if d.y<-.1:actions.append("move_up")
     if d.y>.1:actions.append("move_down")
     for action in actions:Input.action_press(action)
     var contact=false
     var inside=true
     for frame in range(100):
      await physics_frame
      if ground.get_cell_source_id(ground.local_to_map(ground.to_local(player.global_position)))<0:
       inside=false
       break
      for c in range(player.get_slide_collision_count()):
       if player.get_slide_collision(c).get_collider()==body:contact=true
      if contact:break
     for action in actions:Input.action_release(action)
     player.velocity=Vector2.ZERO
     if contact and inside:return true
 return false

func _run():
 if OS.get_environment("REVERIE_E2E_DISABLE_LOCAL_SAVE")!="1":quit(2);return
 change_scene_to_file("res://scenes/world/six_zone_reverie/individual_zones/zone_04_elderwood_grove_standalone.tscn")
 await scene_changed
 for i in range(5):await physics_frame
 zone=current_scene
 player=zone.get("checkpoint_player")
 var city=zone.get_node("Zone")
 ground=city.get_node("GroundTiles/EditableTileMap")
 q.shape=player.get_node("CollisionShape2D").shape
 q.collision_mask=1
 q.collide_with_areas=false
 q.exclude=[player.get_rid()]
 build_reachable()
 # Test isolated from story combat and automatic map transfers; collision stays enabled.
 for p in ["TransferPoints/ToPreviousZone/ToPreviousZoneTrigger","TransferPoints/ToNextZone/ToNextZoneTrigger"]:
  zone.get_node(p).monitoring=false
  zone.get_node(p).set_physics_process(false)
 for key in ["RoyalGatePatrol","RainbowMob"]:
  var n=zone.get_node_or_null(key)
  if n:n.process_mode=Node.PROCESS_MODE_DISABLED
 var targets={}
 for key in ["DrownedOrchidRuins","FloodedLandscape"]:
  var g=city.get_node(key)
  for s in g.find_children("*","Sprite2D",true,false):
   if s.is_visible_in_tree() and s.texture and s.name!="LanternLight" and s.z_index>=0 and s.get_parent().name not in ["StoneTerraces","FloodedPools"]:
    var a=anchor(s)
    targets[str(city.get_path_to(a))]=a
  for s in g.find_children("ArtworkRegion","Polygon2D",true,false):
   if s.is_visible_in_tree() and s.z_index==0:
    var a=anchor(s)
    targets[str(city.get_path_to(a))]=a
 var errors=[]
 var skipped=[]
 var submerged=[]
 var scenic=[]
 var one_sided=[]
 var tested=0
 var directions=0
 var boundaries=0
 for key in targets:
  var a=targets[key]
  var center=a.global_position
  var start=corridor(center)
  if start==null:
   if await approach_boundary(a):
    boundaries+=1
    print("BOUNDARY CONTACT PASS ",key)
   else:
    var point_query=PhysicsPointQueryParameters2D.new()
    point_query.position=center+Vector2(0,-10)
    point_query.collision_mask=1
    var water=root.world_2d.direct_space_state.intersect_point(point_query,32).filter(func(h):return str(h.collider.name) in ["NorthernMirrorCollision","WestFloodplainCollision","EasternLakeCollision","SouthernLagoonCollision","WestPoolBoundary","EastPoolBoundary","OpenWaterCollision","BasinBoundary0","BasinBoundary1","BasinBoundary2","BasinBoundary3"])
    if not water.is_empty():
     submerged.append(key)
    elif not nearby_reachable(center,4):
     scenic.append(key)
    elif await short_side_walk(center):
     one_sided.append(key)
    else:
     skipped.append(key)
   continue
  place(start)
  player.set("input_enabled",true)
  await physics_frame
  var forward=await drive("move_down",center.y+24,true)
  var reverse=await drive("move_up",center.y-24,false)
  if not forward or not reverse:errors.append(key+" forward="+str(forward)+" reverse="+str(reverse))
  directions+=int(forward)+int(reverse)
  tested+=1
  if tested%25==0:print("PLAYER WALK progress ",tested," errors=",errors.size())
 print("PLAYER WALK targets=",targets.size()," tested=",tested," directions=",directions," boundary contacts=",boundaries," submerged=",submerged.size()," isolated scenery=",scenic.size()," one-sided walks=",one_sided.size()," skipped=",skipped.size()," errors=",errors.size())
 for x in skipped:print("NO TWO-SIDED CORRIDOR ",x)
 for e in errors:print("FAILED ",e)
 zone.queue_free()
 for i in range(3):await process_frame
 root.get_node("AudioDirector").stop_all_audio_immediately()
 OS.delay_msec(400)
 for i in range(8):await process_frame
 await create_timer(.35).timeout
 quit(0 if errors.is_empty() and tested>60 and skipped.is_empty() else 1)

