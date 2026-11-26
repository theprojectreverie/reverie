extends SceneTree
func _initialize():call_deferred("_run")
func _run():
 if OS.get_environment("REVERIE_E2E_DISABLE_LOCAL_SAVE")!="1" or not OS.get_user_data_dir().to_lower().contains("reverie_profile_qa_"):
  quit(2)
  return
 var gs=root.get_node("GameState")
 gs.new_game("Performance QA")
 gs.flags["tutorial_complete"]=true
 var cp=load("res://scripts/world/six_zone_reverie/six_zone_checkpoint.gd")
 var baseline_nodes=int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT))
 var baseline_orphans=int(Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT))
 print("PROFILE BASELINE ",snapshot())
 var failed=false
 for cycle in range(2):
  for id in cp.SCENES:
   var start=Time.get_ticks_msec()
   change_scene_to_file(cp.SCENES[id])
   await scene_changed
   for i in range(8):await process_frame
   var ms=Time.get_ticks_msec()-start
   var z=current_scene
   var w=weakref(z)
   var p=weakref(z.checkpoint_player)
   var samples=[]
   for i in range(90):
    await process_frame
    samples.append(root.get_process_delta_time()*1000.0)
   samples.sort()
   print("PROFILE MAP ",cycle+1," ",id," load_ms=",ms," median_frame_ms=",snappedf(samples[45],0.01)," p95_ms=",snappedf(samples[85],0.01)," ",snapshot())
   z.queue_free()
   for i in range(8):await process_frame
   if w.get_ref()!=null or p.get_ref()!=null:
    failed=true
   print("PROFILE RELEASE ",cycle+1," ",id," ",snapshot())
 root.get_node("AudioDirector").stop_all_audio_immediately()
 await create_timer(.5).timeout
 var nodes=int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT))
 var orphans=int(Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT))
 print("PROFILE END nodes_delta=",nodes-baseline_nodes," orphan_delta=",orphans-baseline_orphans," ",snapshot())
 print("PROFILE RESULT ",not failed and orphans<=baseline_orphans)
 quit(1 if failed or orphans>baseline_orphans else 0)
func snapshot():
 return {"static_mb":snappedf(OS.get_static_memory_usage()/1048576.0,0.1),"video_mb":snappedf(Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED)/1048576.0,0.1),"texture_mb":snappedf(Performance.get_monitor(Performance.RENDER_TEXTURE_MEM_USED)/1048576.0,0.1),"nodes":int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT)),"orphans":int(Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT)),"resources":int(Performance.get_monitor(Performance.OBJECT_RESOURCE_COUNT)),"draw_calls":int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME))}
