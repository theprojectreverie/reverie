extends SceneTree
func _initialize():call_deferred("run")
func run():
 var scene=(load("res://scenes/world/six_zone_reverie/willow_farming/windmill.tscn") as PackedScene).instantiate()
 root.add_child(scene)
 var a:AnimationPlayer=scene.get_node("AnimationPlayer")
 var r:Node2D=scene.get_node("RotorPivot")
 var collision:CollisionPolygon2D=scene.get_node("Body/Footprint")
 var points=collision.polygon.duplicate()
 a.play("windmill_spin")
 for i in [0,6,12,18,23]:
  a.seek(float(i),true)
  assert(absf(r.rotation-TAU*float(i)/24.0)<0.002)
  assert(collision.polygon==points)
 assert(a.get_animation("windmill_spin").loop_mode==Animation.LOOP_LINEAR)
 print("WINDMILL ANIMATION: 5 phases, loop, static footprint PASS")
 scene.queue_free()
 await process_frame
 quit(0)

