extends SceneTree
func _initialize():call_deferred("run")
func run():
 if OS.get_environment("REVERIE_E2E_DISABLE_LOCAL_SAVE")!="1":quit(2);return
 var z=load("res://scenes/world/six_zone_reverie/individual_zones/zone_06_ruined_tower_standalone.tscn").instantiate();root.add_child(z)
 var p=z.checkpoint_player
 p.input_enabled=false;p.locomotion_component.set_physics_process(false)
 for i in range(5):await physics_frame
 var boundary=z.get_node("TerrainPerimeter");var poly=boundary.get_node("TerrainOutline").polygon
 var fails=[];var checked=0
 for i in range(poly.size()):
  var a=poly[i];var b=poly[(i+1)%poly.size()];var normal=(b-a).orthogonal().normalized()
  if not Geometry2D.is_point_in_polygon((a+b)*0.5+normal*40,poly):normal=-normal
  for j in range(1,20):
   var edge=a.lerp(b,j/20.0);p.global_position=edge+normal*45
   await physics_frame
   p.move_and_collide(-normal*100);checked+=1
   if not Geometry2D.is_point_in_polygon(p.global_position,poly):fails.append([i,j,p.global_position])
 var center=Vector2.ZERO
 for v in poly:center+=v
 center/=poly.size()
 for corner in poly:
  var inward=(center-corner).normalized()
  p.global_position=corner+inward*80
  await physics_frame
  p.move_and_collide(-inward*160);checked+=1
  if not Geometry2D.is_point_in_polygon(p.global_position,poly):fails.append(["corner",corner,p.global_position])
 print("ACTUAL PLAYER BOUNDARY SWEEPS ",checked," FAILURES ",fails)
 var arrival=z.get_node("TransferPoints/SafeSpawnFromPreviousZone").global_position; var departure=z.get_node("TransferPoints/ToPreviousZone").global_position
 for n in z.get_node("TransferPoints/ToPreviousZone").get_children():
  if n is Area2D:n.monitoring=false
 p.global_position=arrival;await physics_frame
 var gate_clear=not p.test_move(p.global_transform,(departure-arrival)*0.7)
 print("GATE PLAYER CLEAR ",gate_clear," ARRIVAL ",arrival," DEPARTURE ",departure)
 z.queue_free();for i in range(3):await process_frame
 root.get_node("AudioDirector").stop_all_audio_immediately();await create_timer(.5).timeout
 quit(0 if fails.is_empty() and gate_clear else 1)
