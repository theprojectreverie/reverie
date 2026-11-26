extends SceneTree
func _initialize():call_deferred("_run")
func _run():
 if OS.get_environment("REVERIE_E2E_DISABLE_LOCAL_SAVE")!="1":
  quit(2)
  return
 var gs=root.get_node("GameState")
 gs.quest_domain.flags["tutorial_complete"]=true
 gs.quest_domain.flags["village_gerald_defeated"]=true
 change_scene_to_file("res://scenes/world/six_zone_reverie/individual_zones/zone_05_forsaken_ruins_standalone.tscn")
 await scene_changed
 for i in range(8):await process_frame
 var z=current_scene
 var p=z.checkpoint_player
 p.input_enabled=false
 p.locomotion_component.set_physics_process(false)
 var v=p.visual
 for id in ["gerald","lilith","kael","gerald","lilith"]:
  p.set_avatar(id)
  assert(p.avatar_id==id)
  assert(v.character_art_report().has_frames)
  var shared=v.get_node("SharedCharacterEffects")
  var spectral=v.get_node("LilithSpectralEffects")
  for state in [0,1,2,3,4,5,6,7,8]:
   v.animator.play_forced(state,0)
   v._update_sprite_frame()
   await process_frame
   await process_frame
   assert(not shared.visible,"Shared overlay on "+id)
   assert(not spectral.get_node("SpectralHalo").is_visible_in_tree(),"Spectral ring on "+id)
   assert(v._sprite.visible)
  v.animator.play_forced(0,0)
  v._update_sprite_frame()
  for i in range(8):await process_frame
  if DisplayServer.get_name()!="headless":
   await RenderingServer.frame_post_draw
   print("CAPTURE ",id," ",root.get_texture().get_image().save_png("C:/Users/quoth/Downloads/reverie_clean_"+id+".png"))
 print("NO SHARED OR SPECTRAL GEOMETRY; 45 STATE CHECKS AND AVATAR SWITCHES PASS")
 z.queue_free()
 for i in range(3):await process_frame
 root.get_node("AudioDirector").stop_all_audio_immediately()
 await create_timer(.35).timeout
 quit()
