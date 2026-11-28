extends SceneTree
func _initialize():call_deferred("_run")
func _run():
 change_scene_to_file("res://scenes/world/six_zone_reverie/individual_zones/zone_02_royal_gate_standalone.tscn")
 await scene_changed
 for i in range(5):await physics_frame
 var z=current_scene
 var gate=z.get_node("Zone/RoyalGate/WillowFieldsLilyArch")
 var q=PhysicsShapeQueryParameters2D.new()
 var circle=CircleShape2D.new()
 circle.radius=18
 q.shape=circle
 q.collision_mask=1
 q.collide_with_areas=false
 var blocked=0
 for i in range(31):
  var p=gate.global_position+Vector2(-120,-60).lerp(Vector2(120,60),i/30.0)
  q.transform=Transform2D(0,p)
  if not root.world_2d.direct_space_state.intersect_shape(q).is_empty():blocked+=1
 var pillars=0
 for key in ["WestPillar","EastPillar"]:
  q.transform=Transform2D(0,gate.get_node(key).global_position)
  if not root.world_2d.direct_space_state.intersect_shape(q).is_empty():pillars+=1
 print("EXIT clearance: ",31-blocked,"/31; solid pillars ",pillars,"/2")
 if is_instance_valid(current_scene): current_scene.queue_free()
 for i in range(3): await process_frame
 root.get_node("AudioDirector").stop_all_audio_immediately()
 await create_timer(0.35).timeout
 quit(0 if blocked==0 and pillars==2 else 1)

