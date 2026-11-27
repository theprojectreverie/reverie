extends SceneTree
const SCENE="res://scenes/world/six_zone_reverie/individual_zones/zone_05_forsaken_ruins_standalone.tscn"
var player:CharacterBody2D
var layer:TileMapLayer
var touch:Node
var space:PhysicsDirectSpaceState2D
var query:PhysicsShapeQueryParameters2D
var graph:=AStar2D.new()
var ids:Dictionary={}
var frames:=0
func _initialize():call_deferred("run")
func clear_at(p:Vector2)->bool:
 query.transform=Transform2D(0,p+Vector2(0,-10))
 return space.intersect_shape(query,1).is_empty()
func nearest(p:Vector2)->int:
 return graph.get_closest_point(p)
func walk(p:Vector2)->bool:
 var steps:=0
 while player.global_position.distance_to(p)>7.0 and steps<120:
  var diff=p-player.global_position
  touch.set_move_vector(diff.normalized()*clampf(diff.length()/30.0,.22,.85))
  await physics_frame
  if not is_instance_valid(player):return false
  frames+=1
  steps+=1
 touch.release()
 return player.global_position.distance_to(p)<12
func visit(target:Vector2,radius:float)->bool:
 var start:=nearest(player.global_position)
 var end:=nearest(target)
 if graph.get_point_position(end).distance_to(target)>radius:return false
 var path:=graph.get_point_path(start,end)
 if path.is_empty():return false
 for i in range(path.size()):
  if not await walk(path[i]):
   print("STUCK ",player.global_position," waypoint ",path[i]," goal ",target)
   return false
 print("REACHED ",target," actual ",player.global_position," waypoints ",path.size())
 return player.global_position.distance_to(target)<radius+12
func run():
 if OS.get_environment("REVERIE_E2E_DISABLE_LOCAL_SAVE")!="1":quit(2);return
 var gs=root.get_node("GameState")
 gs.quest_domain.flags["tutorial_complete"]=true
 gs.quest_domain.flags.erase("six_zone_checkpoint")
 touch=root.get_node("TouchInput")
 change_scene_to_file(SCENE)
 await scene_changed
 for i in range(8):await physics_frame
 var z=current_scene
 player=z.checkpoint_player
 layer=z.get_node("Zone/GroundTiles/EditableTileMap")
 space=z.get_world_2d().direct_space_state
 query=PhysicsShapeQueryParameters2D.new()
 query.shape=player.get_node("CollisionShape2D").shape
 query.collision_mask=1
 var next_id:=1
 for c in layer.get_used_cells():
  var p:=layer.to_global(layer.map_to_local(c))
  if p.distance_to(Vector2(-1712,816))<110 or p.distance_to(Vector2(600,1650))<125:continue
  if not clear_at(p):continue
  ids[c]=next_id
  graph.add_point(next_id,p,3.5 if layer.get_cell_source_id(c)==24 else 1.0)
  next_id+=1
 for c in ids:
  var a:int=ids[c]
  for n in layer.get_surrounding_cells(c):
   if not ids.has(n):continue
   var b:int=ids[n]
   if b<=a:continue
   var p:=graph.get_point_position(a)
   var r:=graph.get_point_position(b)
   if clear_at(p.lerp(r,.25)) and clear_at(p.lerp(r,.5)) and clear_at(p.lerp(r,.75)):graph.connect_points(a,b)
 print("NAV GRID ",graph.get_point_count()," spawn ",player.global_position)
 Engine.time_scale=2.0
 var goals=[Vector2(-908,1280),Vector2(-950,1365),Vector2(0,1665),Vector2(930,2145),Vector2(-908,1280),Vector2(1500,2350)]
 for goal in goals:
  if not await visit(goal,65):
   push_error("TRAVERSAL FAILED "+str(goal))
   touch.release();quit(1);return
 Engine.time_scale=1.0
 touch.release()
 print("FORSAKEN REAL PLAYER TRAVERSAL PASS: ",frames," frames, ",goals.size()," destinations")
 z.queue_free()
 for i in range(3):await process_frame
 root.get_node("AudioDirector").stop_all_audio_immediately()
 quit(0)
