extends SceneTree
func _initialize():
 call_deferred("_run")
func _run():
 if OS.get_environment("REVERIE_E2E_DISABLE_LOCAL_SAVE")!="1":
  quit(2)
  return
 var gs=root.get_node("GameState")
 gs.quest_domain.flags["tutorial_complete"]=true
 change_scene_to_file("res://scenes/world/six_zone_reverie/individual_zones/zone_05_forsaken_ruins_standalone.tscn")
 await scene_changed
 for i in range(5): await physics_frame
 gs.quest_domain.advance_quest("cassien_resurrection")
 await physics_frame
 var zone=current_scene
 var player=zone.checkpoint_player
 var tiles=zone.get_node("Zone/GroundTiles/EditableTileMap")
 var layers=[tiles,zone.get_node("EntryRoadFromZone04/RoadTiles/EditableTileMap"),zone.get_node("ExitRoadToZone06/RoadTiles/EditableTileMap")]
 var q=PhysicsShapeQueryParameters2D.new()
 q.shape=player.get_node("CollisionShape2D").shape
 q.collision_mask=1
 var space=zone.get_world_2d().direct_space_state
 var routes=[
 [zone.get_node("TransferPoints/ToPreviousZone").global_position,Vector2(-1552,944),Vector2(-1552,1010),Vector2(-1744,1080),Vector2(-1872,1044),Vector2(-172,1894),Vector2(240,1688),Vector2(1568,2352),Vector2(1664,2432)],
 [Vector2(-1110,1425),Vector2(-780,1260),Vector2(-908,1196),Vector2(-1010,1210),Vector2(-1100,1195)]
 ]
 var errors=[]
 for route in routes:
  for i in range(route.size()-1):
   var a:Vector2=route[i]
   var b:Vector2=route[i+1]
   var n=maxi(1,ceili(a.distance_to(b)/8.0))
   for j in range(n+1):
    var p=a.lerp(b,float(j)/n)
    var ground=false
    var paved=false
    for layer in layers:
     var id=layer.get_cell_source_id(layer.local_to_map(layer.to_local(p)))
     if id>=0: ground=true
     if id in [20,25]: paved=true
    q.transform=Transform2D(0,p+Vector2(0,-10))
    if not ground or not paved or not space.intersect_shape(q,8).is_empty():
     errors.append([p,ground,paved,not space.intersect_shape(q,8).is_empty()])
 for prop in zone.get_node("RuinsDecoration").get_children():
  if tiles.get_cell_source_id(tiles.local_to_map(tiles.to_local(prop.global_position)))<0:
   errors.append(["PROP OFF MAP",prop.name,prop.global_position])
 print("PAVING AND ROUTE ERRORS ",errors.size()," sample ",errors.slice(0,20))
 print("BASE TILE COUNT ",tiles.get_used_cells().size())
 root.get_node("AudioDirector").stop_all_audio_immediately()
 await create_timer(0.35).timeout
 quit(0 if errors.is_empty() else 1)
