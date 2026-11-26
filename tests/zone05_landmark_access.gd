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
 var layer=zone.get_node("Zone/GroundTiles/EditableTileMap") as TileMapLayer
 var q=PhysicsShapeQueryParameters2D.new()
 q.shape=zone.checkpoint_player.get_node("CollisionShape2D").shape
 q.collision_mask=1
 var space=zone.get_world_2d().direct_space_state
 var available={}
 for c in layer.get_used_cells():
  if layer.get_cell_source_id(c) not in [20,25]:
   continue
  var p=layer.to_global(layer.map_to_local(c))
  q.transform=Transform2D(0,p+Vector2(0,-10))
  if space.intersect_shape(q,1).is_empty():
   available[c]=true
 var start=layer.local_to_map(layer.to_local(Vector2(-1744,1080)))
 assert(available.has(start),"Start not paved")
 var visited={start:true}
 var queue:Array[Vector2i]=[start]
 var i=0
 while i<queue.size():
  var c=queue[i]
  i+=1
  for n in layer.get_surrounding_cells(c):
   if visited.has(n) or not available.has(n):
    continue
   var a=layer.to_global(layer.map_to_local(c))
   var b=layer.to_global(layer.map_to_local(n))
   var clear=true
   for t in [0.25,0.5,0.75]:
    q.transform=Transform2D(0,a.lerp(b,t)+Vector2(0,-10))
    if not space.intersect_shape(q,1).is_empty():
     clear=false
     break
   if clear:
    visited[n]=true
    queue.append(n)
 var targets={"Northern memorial":Vector2(-300,790),"Eastern fountain":Vector2(1380,1220),"Southern memorial":Vector2(-650,2370),"Far arch":Vector2(390,2670),"Tomb":Vector2(-1100,1100)}
 var errors=[]
 for name in targets:
  var nearest=INF
  for c in visited:
   nearest=minf(nearest,layer.to_global(layer.map_to_local(c)).distance_to(targets[name]))
  print("LANDMARK ",name," nearest connected pavement ",nearest)
  if nearest>110:
   errors.append(name)
 print("CONNECTED LANDMARKS ",targets.size()-errors.size(),"/",targets.size()," reachable tiles ",visited.size()," errors ",errors)
 root.get_node("AudioDirector").stop_all_audio_immediately()
 await create_timer(0.35).timeout
 quit(0 if errors.is_empty() else 1)
