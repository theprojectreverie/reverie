extends SceneTree
var failures=[]
func _initialize():call_deferred("_run")
func check(ok:bool,label:String):
 if not ok:
  failures.append(label)
  push_error(label)
func _run():
 if OS.get_environment("REVERIE_E2E_DISABLE_LOCAL_SAVE")!="1":
  quit(2)
  return
 var paths=["res://scenes/ui/opening_cinematic.tscn","res://scenes/enemies/boss/gerald_before_the_fall.tscn","res://scenes/enemies/boss/gerald_boss_intro.tscn"]
 var shots=0
 for path in paths:
  var scene=load(path).instantiate()
  root.add_child(scene)
  await process_frame
  var pb=scene.playback_component
  pb.set_auto_play(false)
  var prefetch=scene.presentation_component._prefetch
  for i in range(pb.shots.size()):
   check(pb.shot_index==i,path+" shot index")
   check(scene.get_node("Artwork").texture.resource_path==str(pb.shots[i].image),path+" artwork")
   var next=str(pb.shots[i+1].image) if i+1<pb.shots.size() else ""
   check(prefetch.pending_path==next,path+" bounded next shot")
   shots+=1
   if i+1<pb.shots.size():
    await create_timer(.05).timeout
    pb.request_advance()
    await create_timer(.42).timeout
  scene.queue_free()
  await process_frame
  check(prefetch.pending_path.is_empty(),path+" cleanup")
  var skip=load(path).instantiate()
  root.add_child(skip)
  var skipped_prefetch=skip.presentation_component._prefetch
  skip._finish()
  await create_timer(1.0).timeout
  check(skipped_prefetch.pending_path.is_empty(),path+" skip cleanup")
  skip.queue_free()
  await process_frame
  print("PREFETCH PASS ",path)
 root.get_node("AudioDirector").stop_all_audio_immediately()
 await create_timer(.35).timeout
 print("CINEMATIC PREFETCH RESULT shots=",shots," errors=",failures)
 quit(0 if failures.is_empty() else 1)
