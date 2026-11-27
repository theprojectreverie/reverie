extends SceneTree
func _initialize():call_deferred("run")
func run():
 var mill=(load("res://scenes/world/six_zone_reverie/willow_farming/windmill.tscn") as PackedScene).instantiate()
 root.add_child(mill)
 var a:AnimationPlayer=mill.get_node("AnimationPlayer")
 var rotor:Node2D=mill.get_node("RotorPivot")
 a.play("windmill_spin")
 var pos=rotor.position
 for t in [0.0,6.0,12.0,18.0,23.9]:
  a.seek(t,true)
  assert(absf(rotor.rotation-t*TAU/24.0)<0.02)
  assert(rotor.position==pos)
 assert(a.get_animation("windmill_spin").loop_mode==Animation.LOOP_LINEAR)
 print("WINDMILL ROTATION AND FIXED HUB PASS")
 mill.queue_free()
 await process_frame
 quit(0)


