extends SceneTree
var failures: Array[String] = []
func _initialize():
 call_deferred("_run")
func check(ok: bool, label: String):
 if not ok:
  failures.append(label)
  print("FAIL ",label)
func _run():
 if OS.get_environment("REVERIE_E2E_DISABLE_LOCAL_SAVE")!="1":
  quit(2)
  return
 var audio=root.get_node("AudioDirector")
 var counts=[17,17]
 var totals=[211.5,211.2]
 var chapters=["res://scenes/enemies/boss/gerald_before_the_fall.tscn","res://scenes/enemies/boss/gerald_boss_intro.tscn"]
 var ids=["gerald_childhood","gerald_tragedy"]
 for chapter in range(2):
  var id=ids[chapter]
  check(audio.play_track(id,0.05),"music start "+id)
  var intro=load(chapters[chapter]).instantiate()
  intro.music_track_id=id
  root.add_child(intro)
  await create_timer(0.25).timeout
  var pb=intro.get_node("Playback")
  check(pb.shots.size()==counts[chapter],"all authored shots "+id)
  check(absf(pb._total_duration-totals[chapter])<0.01,"duration "+id)
  check(audio.music_position_for(id)>=0.0,"audio clock active "+id)
  check(intro.get_node("Backdrop").color.a==1.0,"opaque backdrop "+id)
  for i in range(pb.shots.size()):
   var shot=pb.shots[i]
   check(ResourceLoader.exists(shot.image),"texture exists "+shot.image)
   check(pb.shot_index==i,"cue order "+str(i))
   var boundary=pb._cue_end_times[i]
   check(not pb.cue_due(boundary-0.4) and pb.cue_due(boundary-0.25),"cue threshold "+str(i))
   check(intro.get_node("Artwork").texture.resource_path==shot.image,"displayed texture "+str(i))
   # Move the actual audio stream just before this cue, then let the real
   # synchronized playback loop cross it. No synthetic shot advance.
   audio._player.seek(boundary-0.24)
   var deadline=Time.get_ticks_msec()+2500
   while pb.shot_index==i and Time.get_ticks_msec()<deadline:
    await process_frame
   check(pb.shot_index==i+1,"audio drove next shot "+str(i))
   if pb.shot_index==i:
    print("CLOCK ",audio.music_position_for(id)," BOUNDARY ",boundary)
    quit(1)
    return
  check(not pb.active,"chapter reached terminal state")
  await create_timer(0.9).timeout
  intro.queue_free()
  await process_frame
  print("CUE_CHAPTER_PASS ",id," shots=",counts[chapter]," duration=",totals[chapter])
 print("CUE_SYNC_RESULT ",failures)
 quit(0 if failures.is_empty() else 1)