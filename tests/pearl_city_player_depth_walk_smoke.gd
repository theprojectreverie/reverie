extends SceneTree
var zone:Node2D
var player:CharacterBody2D
var ground:TileMapLayer
var q=PhysicsShapeQueryParameters2D.new()
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
 q.transform=Transform2D(0,p+Vector2(0,-7))
 return root.world_2d.direct_space_state.intersect_shape(q,1).is_empty()
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
 if bodies.is_empty():return false
 var center=a.global_position
 for body in bodies:
  var polys=body.find_children("*","CollisionPolygon2D",true,false)
  for poly in polys:
   var avg=Vector2.ZERO
   for v in poly.polygon:avg+=poly.to_global(v)
   center=avg/poly.polygon.size()+Vector2(0,7)
   for d in [Vector2.UP,Vector2.DOWN,Vector2.LEFT,Vector2.RIGHT,Vector2(-1,-1).normalized(),Vector2(1,-1).normalized(),Vector2(-1,1).normalized(),Vector2(1,1).normalized()]:
    for distance in [36,48,64,80,100,128,160]:
     var start=center-d*distance
     if not clear(start):continue
     var hit=false
     for k in range(4,distance+4,4):
      var p=start+d*k
      if ground.get_cell_source_id(ground.local_to_map(ground.to_local(p)))<0:break
      q.transform=Transform2D(0,p+Vector2(0,-7))
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
 change_scene_to_file("res://scenes/world/six_zone_reverie/individual_zones/zone_02_royal_gate_standalone.tscn")
 await scene_changed
 for i in range(5):await physics_frame
 zone=current_scene
 player=zone.get("checkpoint_player")
 var city=zone.get_node("Zone")
 ground=city.get_node("GroundTiles/EditableTileMap")
 var circle=CircleShape2D.new()
 circle.radius=12
 q.shape=circle
 q.collision_mask=1
 q.collide_with_areas=false
 # Test isolated from story combat and automatic map transfers; collision stays enabled.
 for p in ["TransferPoints/ToPreviousZone/ToPreviousZoneTrigger","TransferPoints/ToNextZone/ToNextZoneTrigger"]:
  zone.get_node(p).monitoring=false
  zone.get_node(p).set_physics_process(false)
 for key in ["RoyalGatePatrol","RainbowMob"]:
  var n=zone.get_node_or_null(key)
  if n:n.process_mode=Node.PROCESS_MODE_DISABLED
 var targets={}
 for key in ["RoyalGate","CentralPark","MarketStreet","ResidentialOutskirts","Sanctuary","CityLifePreview"]:
  var g=city.get_node(key)
  for s in g.find_children("*","Sprite2D",true,false):
   if s.is_visible_in_tree() and s.texture and s.name!="LanternLight":
    var a=anchor(s)
    targets[str(city.get_path_to(a))]=a
  for s in g.find_children("ArtworkRegion","Polygon2D",true,false):
   if s.is_visible_in_tree() and s.z_index==0:
    var a=anchor(s)
    targets[str(city.get_path_to(a))]=a
 var errors=[]
 var skipped=[]
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
 print("PLAYER WALK targets=",targets.size()," tested=",tested," directions=",directions," boundary contacts=",boundaries," skipped=",skipped.size()," errors=",errors.size())
 for x in skipped:print("NO TWO-SIDED CORRIDOR ",x)
 for e in errors:print("FAILED ",e)
 zone.queue_free()
 for i in range(3):await process_frame
 root.get_node("AudioDirector").stop_all_audio_immediately()
 OS.delay_msec(400)
 for i in range(8):await process_frame
 await create_timer(.35).timeout
 quit(0 if errors.is_empty() and tested>100 else 1)

