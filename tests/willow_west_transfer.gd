extends SceneTree
func _initialize():call_deferred("_run")
func _run():
 if OS.get_environment("REVERIE_E2E_DISABLE_LOCAL_SAVE")!="1":
  quit(2)
  return
 var gs=root.get_node("GameState")
 gs.quest_domain.flags["tutorial_complete"]=true
 change_scene_to_file("res://scenes/world/six_zone_reverie/individual_zones/zone_03_willow_fields_standalone.tscn")
 await scene_changed
 for i in range(5):await physics_frame
 var z=current_scene
 var marker=z.get_node("TransferPoints/ToPreviousZone")
 z.checkpoint_player.global_position=marker.global_position
 for i in range(120):
  await physics_frame
  if current_scene!=z:break
 var ok=current_scene!=null and current_scene.name==&"StandaloneZone02"
 print("WEST MARKER ACTUAL AREA TRANSFER ",ok)
 if is_instance_valid(current_scene):current_scene.queue_free()
 for i in range(3):await process_frame
 root.get_node("AudioDirector").stop_all_audio_immediately()
 await create_timer(0.35).timeout
 quit(0 if ok else 1)
