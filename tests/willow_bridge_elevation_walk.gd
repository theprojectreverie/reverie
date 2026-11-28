extends SceneTree
var failures: Array[String] = []
var samples := 0
var peak := 0.0
var previous := 0.0
var max_jump := 0.0
func _initialize(): call_deferred("run")
func run():
 if OS.get_environment("REVERIE_E2E_DISABLE_LOCAL_SAVE") != "1": quit(2); return
 root.get_node("GameState").quest_domain.flags["tutorial_complete"] = true
 change_scene_to_file("res://scenes/world/six_zone_reverie/individual_zones/zone_03_willow_fields_standalone.tscn")
 await scene_changed
 for i in range(8): await physics_frame
 var z = current_scene
 var p = z.checkpoint_player
 var bridge = z.get_node("Zone/BridgeElevation")
 var touch = root.get_node("TouchInput")
 var base_y: float = p.visual.position.y
 p.global_position = Vector2(930,1703)
 p.reset_physics_interpolation()
 await physics_frame
 var cam = z.get_node("ZoneCamera")
 if DisplayServer.get_name() != "headless":
  z.get_node("UI").hide()
  p.get_node("Camera2D").enabled = false
  cam.enabled = true
  cam.make_current()
  cam.position = Vector2(1120,1550)
  cam.zoom = Vector2(1.3,1.3)
 var targets = [Vector2(998,1669),Vector2(1045,1645.5),Vector2(1100,1618),Vector2(1165,1585.5),Vector2(1240,1548),Vector2(1300,1518),Vector2(1165,1585.5),Vector2(1100,1618),Vector2(1045,1645.5),Vector2(930,1703)]
 for i in range(targets.size()):
  var guard := 0
  while p.global_position.distance_to(targets[i]) > 8 and guard < 700:
   var d: Vector2 = targets[i] - p.global_position
   touch.set_move_vector(d.normalized() * clampf(d.length()/40.0,0.22,0.65))
   await physics_frame
   var lift: float = bridge.elevation_at(p.global_position)
   peak = maxf(peak,lift)
   max_jump = maxf(max_jump,absf(lift-previous))
   previous = lift
   samples += 1
   if absf(p.visual.position.y - (base_y-lift)) > 5.0: failures.append("visual mismatch at " + str(p.global_position))
   guard += 1
  touch.release()
  for j in range(10): await physics_frame
  if p.global_position.distance_to(targets[i]) > 22: failures.append("blocked target " + str(i) + " " + str(p.global_position))
  print("BRIDGE POINT ",i," pos=",p.global_position," lift=",bridge.elevation_at(p.global_position)," visual=",p.visual.position)
  if DisplayServer.get_name() != "headless" and i in [0,1,2,3,4,5,7,9]:
   await RenderingServer.frame_post_draw
   root.get_texture().get_image().save_png(OS.get_environment("TEMP")+"/reverie_map_concepts/bridge_walk_"+str(i)+".png")
  if not failures.is_empty(): break
 var q := PhysicsShapeQueryParameters2D.new()
 q.shape = p.get_node("CollisionShape2D").shape
 q.collision_mask = 1
 for rail_name in ["FarRail", "NearRail"]:
  var rail = bridge.get_node(rail_name)
  var footprint = rail.get_node("Footprint")
  var center := Vector2.ZERO
  for v in footprint.polygon: center += v
  center /= footprint.polygon.size()
  q.transform = Transform2D(0, footprint.to_global(center))
  if not z.get_world_2d().direct_space_state.intersect_shape(q,32).any(func(h): return h.collider == rail): failures.append("missing rail collision " + rail_name)
 if peak < 40 or max_jump > 12: failures.append("elevation profile invalid")
 if absf(p.visual.position.y-base_y)>0.5: failures.append("height not reset")
 print("BRIDGE WALK samples=",samples," peak=",peak," max_jump=",max_jump," failures=",failures.slice(0,12))
 z.queue_free()
 for i in range(3): await process_frame
 root.get_node("AudioDirector").stop_all_audio_immediately()
 await create_timer(.35).timeout
 quit(0 if failures.is_empty() else 1)
