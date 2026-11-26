extends SceneTree
func _initialize():
 call_deferred("run")
func run():
 var frames=load("res://assets/enemies/gerald_fallen/walk_directions.tres") as SpriteFrames
 var scene=load("res://scenes/enemies/boss/gerald_fallen_walk_preview.tscn").instantiate()
 root.add_child(scene)
 var ok=frames!=null and frames.get_animation_names().size()==8
 for d in ["s","se","e","ne","n","nw","w","sw"]:
  var clip=StringName("walk_"+d)
  var actor=scene.get_node("Walk_"+d.to_upper()) as AnimatedSprite2D
  var valid=frames.get_frame_count(clip)==16 and frames.get_animation_loop(clip) and frames.get_frame_texture(clip,15).get_size()==Vector2(128,128)
  actor.play(clip)
  actor.set_frame_and_progress(0,0.0)
  print(clip," valid=",valid)
  ok=ok and valid
 await create_timer(0.5).timeout
 for actor in scene.get_children():
  ok=ok and actor.is_playing() and actor.frame>0
 print("GERALD_WALK_REVIEW_PASS=",ok)
 quit(0 if ok else 1)
