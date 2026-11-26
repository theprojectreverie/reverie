extends SceneTree
const BASE = "res://scenes/world/six_zone_reverie/individual_zones/"
const NAMES = ["01_royal_gardens","02_royal_gate","03_willow_fields","04_elderwood_grove","05_forsaken_ruins","06_ruined_tower"]
func _initialize():
 call_deferred("_run")
func _run():
 if OS.get_environment("REVERIE_E2E_DISABLE_LOCAL_SAVE") != "1":
  quit(2)
  return
 var failures: Array[String] = []
 var gs = root.get_node("GameState")
 gs.quest_domain.flags["tutorial_complete"]=true
 gs.quest_domain.flags.erase("six_zone_checkpoint")
 var transfer = load("res://scripts/world/six_zone_reverie/zone_transfer_trigger.gd")
 for i in range(-1,6):
  var village = i == -1
  var label = "village" if village else NAMES[i]
  transfer.pending_arrival=&"" if i<=0 else &"ToPreviousZone"
  var scene_path = "res://scenes/world/village/imported_village/village_playable.tscn" if village else BASE+"zone_"+label+"_standalone.tscn"
  if change_scene_to_file(scene_path)!=OK:
   failures.append(label+" load failed")
   continue
  await scene_changed
  for f in range(4):await physics_frame
  var zone=current_scene
  var player=zone.get("checkpoint_player")
  player.input_enabled=false
  var entry:Vector2=player.global_position
  var marker=zone.get_node_or_null("TransferPoints/ToNextZone")
  if marker==null:marker=zone.get_node_or_null("Zone/GothicArchitecture")
  var dest:Vector2=marker.global_position if marker!=null else Vector2(0,1450)
  if i==5:dest=Vector2(0,1100)
  var shape=player.get_node("CollisionShape2D")
  var query=PhysicsShapeQueryParameters2D.new()
  query.shape=shape.shape
  query.collision_mask=1
  query.exclude=[player.get_rid()]
  var space=player.get_world_2d().direct_space_state
  var grid=AStarGrid2D.new()
  grid.region=Rect2i(-110,-42,228,227) if village else Rect2i(-162,-10,325,180)
  grid.cell_size=Vector2(20,20)
  grid.diagonal_mode=AStarGrid2D.DIAGONAL_MODE_ONLY_IF_NO_OBSTACLES
  grid.update()
  var open_count=0
  for y in range(grid.region.position.y,grid.region.end.y):
   for x in range(grid.region.position.x,grid.region.end.x):
    var point=Vector2(x,y)*20.0
    # Stay on the authored 100x100 diamond, with 60px margin for transition roads.
    var within=absf(point.x)/3200.0+absf(point.y-1584.0)/1584.0<=1.035
    if village:
     within=false
     for layer_name in ["grass","dirt","road"]:
      var terrain=zone.get_node_or_null("VillageMap/"+layer_name) as TileMapLayer
      if terrain!=null and terrain.get_cell_source_id(terrain.local_to_map(terrain.to_local(point)))>=0:
       within=true
       break
    query.transform=Transform2D(0.0,player.scale,0.0,point+shape.position*player.scale)
    var free=within and space.intersect_shape(query,1).is_empty()
    grid.set_point_solid(Vector2i(x,y),not free)
    if free:open_count+=1
  var start=nearest(grid,entry)
  var finish=nearest(grid,dest)
  if start==Vector2i(999,999) or finish==Vector2i(999,999):
   failures.append(label+" missing nearby walkable cell")
   continue
  var path=PackedVector2Array()
  for attempt in range(32):
   path=grid.get_point_path(start,finish)
   if path.is_empty():break
   var bad=Vector2i(999,999)
   for j in range(1,path.size()):
    query.transform=Transform2D(0.0,player.scale,0.0,path[j-1]+shape.position*player.scale)
    query.motion=path[j]-path[j-1]
    if space.cast_motion(query)[0]<0.999:
     bad=Vector2i(roundi(path[j].x/20),roundi(path[j].y/20))
     break
   if bad==Vector2i(999,999):break
   if bad==finish or bad==start:break
   grid.set_point_solid(bad,true)
   print("Reroute around narrow obstruction ",bad)
  print("WALK ",label," start=",entry," goal=",dest," nodes=",path.size()," open=",open_count," start_gap=",entry.distance_to(Vector2(start)*20)," end_gap=",dest.distance_to(Vector2(finish)*20))
  # Verify every segment with a swept collision shape, not just endpoints.
  var blocked_segments=0
  var previous=entry
  if not path.is_empty():
   for point in path:
    query.transform=Transform2D(0.0,player.scale,0.0,previous+shape.position*player.scale)
    query.motion=point-previous
    var cast=space.cast_motion(query)
    if cast[0]<0.999:
     blocked_segments+=1
     print("BLOCKED ",previous," -> ",point," fraction=",cast[0])
    previous=point
   query.transform=Transform2D(0.0,player.scale,0.0,previous+shape.position*player.scale)
   query.motion=dest-previous
   if space.cast_motion(query)[0]<0.999:blocked_segments+=1
  print("SWEEP ",label," blocked_segments=",blocked_segments)
  if path.is_empty() or blocked_segments>0:failures.append(label)
 print("WALKABILITY FAILURES ",failures)
 quit(0 if failures.is_empty() else 1)
func nearest(grid:AStarGrid2D, p:Vector2)->Vector2i:
 var c=Vector2i(roundi(p.x/20),roundi(p.y/20))
 var best=Vector2i(999,999)
 var d=INF
 for y in range(-3,4):
  for x in range(-3,4):
   var n=c+Vector2i(x,y)
   if grid.is_in_boundsv(n) and not grid.is_point_solid(n) and p.distance_to(Vector2(n)*20)<d:
    best=n
    d=p.distance_to(Vector2(n)*20)
 return best