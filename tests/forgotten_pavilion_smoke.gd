extends SceneTree
func _initialize(): call_deferred("_run")
func _run():
 if OS.get_environment("REVERIE_E2E_DISABLE_LOCAL_SAVE") != "1":
  quit(2)
  return
 root.get_node("GameState").quest_domain.flags["tutorial_complete"]=true
 change_scene_to_file("res://scenes/world/six_zone_reverie/individual_zones/zone_03_willow_fields_standalone.tscn")
 await scene_changed
 for i in range(8): await physics_frame
 var z=current_scene
 var p=z.get_node("Zone/ForgottenPavilion")
 var ground=z.get_node("Zone/GroundTiles/EditableTileMap")
 var q=PhysicsShapeQueryParameters2D.new()
 q.shape=z.checkpoint_player.get_node("CollisionShape2D").shape
 q.collision_mask=1
 var space=z.get_world_2d().direct_space_state
 var errs=[]
 for child in p.get_children():
  if child is StaticBody2D:
   var shape=child.get_node("Footprint")
   var center=Vector2.ZERO
   for v in shape.polygon: center+=v
   center/=shape.polygon.size()
   q.transform=Transform2D(0,shape.to_global(center))
   if space.intersect_shape(q,1).is_empty(): errs.append("missing collision "+child.name)
 for tile in p.get_node("CourtyardPaving").get_children():
  var id=ground.get_cell_source_id(ground.local_to_map(ground.to_local(tile.global_position)))
  if id<0: errs.append("outside ground "+str(tile.global_position))
 var points=[p.get_node("Entrance").global_position,p.to_global(Vector2(122,162)),p.to_global(Vector2(74,111)),p.get_node("BossCourtyard").global_position]
 for i in range(points.size()-1):
  for j in range(31):
   var pos=points[i].lerp(points[i+1],float(j)/30.0)
   q.transform=Transform2D(0,pos+Vector2(0,-10))
   if not space.intersect_shape(q,1).is_empty(): errs.append("blocked route "+str(pos))
 print("PAVILION CHECK errors=",errs.size()," ",errs.slice(0,20)," props=",p.get_child_count()-3)
 if DisplayServer.get_name()!="headless":
  var player=z.checkpoint_player
  player.global_position=p.get_node("BossCourtyard").global_position
  var cam=player.get_node("Camera2D")
  cam.call("set_base_zoom",0.85)
  for i in range(15): await process_frame
  await RenderingServer.frame_post_draw
  var dest=OS.get_environment("TEMP")+"/reverie_map_concepts/pavilion_placed.png"
  root.get_texture().get_image().save_png(dest)
  print("CAPTURE ",dest)
 z.queue_free()
 for i in range(3): await process_frame
 root.get_node("AudioDirector").stop_all_audio_immediately()
 await create_timer(0.35).timeout
 quit(0 if errs.is_empty() else 1)
