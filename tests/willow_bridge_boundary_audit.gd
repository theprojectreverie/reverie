extends SceneTree
var errs: Array[String]=[]
func _initialize():call_deferred("run")
func run():
 if OS.get_environment("REVERIE_E2E_DISABLE_LOCAL_SAVE")!="1":quit(2);return
 root.get_node("GameState").quest_domain.flags["tutorial_complete"]=true
 change_scene_to_file("res://scenes/world/six_zone_reverie/individual_zones/zone_03_willow_fields_standalone.tscn")
 await scene_changed
 for i in range(8):await physics_frame
 var z=current_scene
 var p=z.checkpoint_player
 var bridge=z.get_node("Zone/BridgeElevation")
 var water=z.get_node("Zone/WillowStream/WillowRiverContinuousArt")
 var space=z.get_world_2d().direct_space_state
 var q=PhysicsPointQueryParameters2D.new();q.collision_mask=1
 var checked=0
 for y in range(260,2400,8):
  for x in range(-150,1820,8):
   var pt=Vector2(x,y)
   if not Geometry2D.is_point_in_polygon(pt,water.polygon):continue
   var gp=water.to_global(pt)
   var lateral=gp.x*.5+gp.y-2168
   if absf(lateral)<=42.1:continue
   q.position=gp
   if not space.intersect_point(q,8).any(func(h):return str(h.collider.name) in ["UpstreamWater","DownstreamWater"]):
    if errs.size()<20:errs.append("unblocked water "+str(gp))
   checked+=1
 var touch=root.get_node("TouchInput")
 var contacts=0
 for x in [1040.0,1100.0,1160.0,1210.0]:
  for side in [-1,1]:
   p.global_position=Vector2(x,2168-x*.5);p.velocity=Vector2.ZERO;p.reset_physics_interpolation()
   await physics_frame
   touch.set_move_vector(Vector2(0,side))
   var hit=false
   for frame in range(40):
    await physics_frame
    for i in range(p.get_slide_collision_count()):
     if str(p.get_slide_collision(i).get_collider().name) in ["FarRail","NearRail","UpstreamWater","DownstreamWater"]:hit=true
    if hit:break
   touch.release();p.velocity=Vector2.ZERO
   if hit:contacts+=1
   else:errs.append("missing side collision "+str(x)+" "+str(side))
 print("RIVER COVERAGE ",checked," SIDE CONTACTS ",contacts,"/8 ERRORS ",errs)
 z.queue_free()
 for i in range(3):await process_frame
 root.get_node("AudioDirector").stop_all_audio_immediately()
 await create_timer(.35).timeout
 quit(0 if errs.is_empty() else 1)
