extends SceneTree
func _initialize():call_deferred("_run")
func _run():
 if OS.get_environment("REVERIE_E2E_DISABLE_LOCAL_SAVE")!="1":
  quit(2)
  return
 root.get_node("GameState").quest_domain.flags["tutorial_complete"]=true
 change_scene_to_file("res://scenes/world/six_zone_reverie/individual_zones/zone_04_elderwood_grove_standalone.tscn")
 await scene_changed
 for i in range(8):await physics_frame
 var z=current_scene
 var p=z.get_node("Zone/DrownedOrchidRuins")
 var l=z.get_node("Zone/GroundTiles/EditableTileMap")
 var player=z.checkpoint_player
 var q=PhysicsShapeQueryParameters2D.new()
 q.shape=player.get_node("CollisionShape2D").shape
 q.collision_mask=1
 var space=z.get_world_2d().direct_space_state
 var errs=[]
 for node in p.get_node("StoneTerraces").get_children()+p.get_node("FloodedPools").get_children():
  if l.get_cell_source_id(l.local_to_map(l.to_local(node.global_position)))<0:errs.append("tile outside terrain "+str(node.global_position))
 for node in p.get_children():
  if node is StaticBody2D:
   for shape in node.get_children():
    if shape is CollisionPolygon2D:
     var c=Vector2.ZERO
     for v in shape.polygon:c+=v
     c/=shape.polygon.size()
     q.transform=Transform2D(0,shape.to_global(c))
     if space.intersect_shape(q,1).is_empty():errs.append("missing footprint "+node.name)
 var route=[p.get_node("Entrance").global_position,p.to_global(Vector2(-200,126)),p.to_global(Vector2(-125,91)),p.get_node("OrchidSoulEncounter").global_position]
 for i in range(route.size()-1):
  for j in range(31):
   var pos=route[i].lerp(route[i+1],float(j)/30.0)
   q.transform=Transform2D(0,pos+Vector2(0,-10))
   if not space.intersect_shape(q,1).is_empty():errs.append("blocked entrance "+str(pos))
 print("ORCHID RUINS CHECK errors=",errs.size()," ",errs.slice(0,20))
 if DisplayServer.get_name()!="headless":
  player.global_position=p.get_node("OrchidSoulEncounter").global_position
  var cam=z.get_node("ZoneCamera")
  cam.position=p.global_position+Vector2(0,-10)
  cam.zoom=Vector2(.83,.83)
  cam.make_current()
  for i in range(15):await process_frame
  await RenderingServer.frame_post_draw
  root.get_texture().get_image().save_png(OS.get_environment("TEMP")+"/reverie_map_concepts/orchid_ruins_placed.png")
  cam.position=Vector2(64,1616)
  cam.zoom=Vector2(.18,.18)
  for i in range(12):await process_frame
  await RenderingServer.frame_post_draw
  root.get_texture().get_image().save_png(OS.get_environment("TEMP")+"/reverie_map_concepts/elderwood_after.png")
 z.queue_free()
 for i in range(3):await process_frame
 root.get_node("AudioDirector").stop_all_audio_immediately()
 await create_timer(.35).timeout
 quit(0 if errs.is_empty() else 1)
