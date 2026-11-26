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
 var ground=z.get_node("Zone/GroundTiles/EditableTileMap") as TileMapLayer
 var layers=[ground]
 for name in ["EntryRoadFromZone02","ExitRoadToZone04","ExitRoadExtension"]:
  layers.append(z.get_node(name+"/RoadTiles/EditableTileMap"))
 var q=PhysicsShapeQueryParameters2D.new()
 q.shape=z.checkpoint_player.get_node("CollisionShape2D").shape
 q.collision_mask=1
 var space=z.get_world_2d().direct_space_state
 var routes=[
 [Vector2(-2720,1360),Vector2(-560,2448),Vector2(1896,1220),Vector2(3008,1776),Vector2(3008,1744)],
 [Vector2(-2318,1569),Vector2(-800,810),Vector2(958,1689)],
 [Vector2(-800,810),Vector2(-640,730)],
 [Vector2(-2200,1628),Vector2(-2204,1716)],
 [Vector2(1896,1220),Vector2(1770,1157)],
 [Vector2(900,1700),Vector2(958,1689),Vector2(1420,1458)]
 ]
 var errors=[]
 var samples=0
 for route in routes:
  for i in range(route.size()-1):
   var a:Vector2=route[i]
   var b:Vector2=route[i+1]
   var n=maxi(1,ceili(a.distance_to(b)/8.0))
   for j in range(n+1):
    var p=a.lerp(b,float(j)/n)
    var paved=false
    for l in layers:
     var id=l.get_cell_source_id(l.local_to_map(l.to_local(p)))
     if id>1:paved=true
    q.transform=Transform2D(0,p+Vector2(0,-10))
    var blocked=not space.intersect_shape(q,1).is_empty()
    if not paved or blocked:errors.append([p,paved,blocked])
    samples+=1
 print("EXACT ROUTE SAMPLES ",samples," ERRORS ",errors.size()," ",errors.slice(0,20))
 z.queue_free()
 for i in range(3):await process_frame
 root.get_node("AudioDirector").stop_all_audio_immediately()
 await create_timer(0.35).timeout
 quit(0 if errors.is_empty() else 1)
