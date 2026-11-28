extends SceneTree

func _initialize() -> void:
 call_deferred("_run")

func _run() -> void:
 if OS.get_environment("REVERIE_E2E_DISABLE_LOCAL_SAVE") != "1":
  quit(2)
  return
 change_scene_to_file("res://scenes/world/six_zone_reverie/individual_zones/zone_02_royal_gate_standalone.tscn")
 await scene_changed
 for i in range(5): await physics_frame
 var zone=current_scene
 var city=zone.get_node("Zone")
 var space=root.world_2d.direct_space_state
 var point=PhysicsPointQueryParameters2D.new()
 point.collision_mask=1
 point.collide_with_areas=false
 var count=0
 var triangles=0
 var errors=[]
 for c in city.find_children("*","CollisionPolygon2D",true,false):
  var body=c.get_parent() as StaticBody2D
  if body==null:continue
  count+=1
  var ids=Geometry2D.triangulate_polygon(c.polygon)
  if c.disabled or body.collision_layer&1==0 or ids.is_empty():
   errors.append(str(city.get_path_to(c))+" invalid or disabled")
   continue
  for i in range(0,ids.size(),3):
   point.position=c.to_global((c.polygon[ids[i]]+c.polygon[ids[i+1]]+c.polygon[ids[i+2]])/3.0)
   triangles+=1
   var hits=space.intersect_point(point,32)
   if not hits.any(func(h):return h.collider==body):
    errors.append(str(city.get_path_to(c))+" missing physical contact")
 var life=city.get_node("CityLifePreview")
 var q=PhysicsShapeQueryParameters2D.new()
 var circle=CircleShape2D.new()
 circle.radius=8
 q.shape=circle
 q.collision_mask=1
 q.collide_with_areas=false
 var citizens=0
 var moving_samples=0
 for n in life.get_children():
  if not n is Node2D:continue
  citizens+=1
  q.transform=Transform2D(0,n.global_position)
  if not space.intersect_shape(q,1).is_empty():
   errors.append(str(n.name)+" overlaps solid object")
  var anim=n.get_node_or_null("Stroll") as AnimationPlayer
  if anim:
   var a=anim.get_animation(anim.current_animation)
   if a:
    for t in range(a.get_track_count()):
     if not str(a.track_get_path(t)).ends_with(":position"):continue
     for j in range(41):
      var pos=a.value_track_interpolate(t,a.length*j/40.0)
      if pos is Vector2:
       moving_samples+=1
       q.transform=Transform2D(0,life.to_global(pos))
       if not space.intersect_shape(q,1).is_empty():
        errors.append(str(n.name)+" obstructed animated route")
 for path in ["RoyalGate/Gate/ProvisionalAsset","RoyalGate/WillowFieldsLilyArch"]:
  var arch=city.get_node(path)
  if not arch.y_sort_enabled or not arch.has_node("WestDepthPillar") or not arch.has_node("EastDepthPillar") or not arch.has_node("ArchOverhead"):
   errors.append(path+" missing depth layers")
  else:
   if arch.get_node("WestDepthPillar/ArtworkRegion").z_index!=0 or arch.get_node("EastDepthPillar/ArtworkRegion").z_index!=0 or arch.get_node("ArchOverhead/ArtworkRegion").z_index!=1:
    errors.append(path+" incorrect depth layers")
 print("PEARL PHYSICS polygons=",count," sampled triangles=",triangles," citizens=",citizens," moving samples=",moving_samples," errors=",errors.size())
 for e in errors:print(e)
 var passed=errors.is_empty() and count>=261 and citizens>=22 and moving_samples>=287
 zone.queue_free()
 for i in range(3):await process_frame
 root.get_node("AudioDirector").stop_all_audio_immediately()
 await create_timer(.35).timeout
 quit(0 if passed else 1)
