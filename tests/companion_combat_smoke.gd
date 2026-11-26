extends SceneTree
func _initialize():call_deferred("run")
func run():
 if OS.get_environment("REVERIE_E2E_DISABLE_LOCAL_SAVE")!="1":quit(2);return
 root.get_node("GameState").new_game("Companion QA")
 var battle=load("res://scenes/ui/combat_screen.tscn").instantiate();battle.group_id="tutorial_fairy_spar";root.add_child(battle)
 for i in range(8):await process_frame
 battle._turn_token+=1;battle._auto=false
 var actor=battle._actor_for_uid(battle.engine.combatants[-1].uid);var target=battle._actor_for_uid(battle.engine.combatants[0].uid)
 assert(actor!=null and target!=null and actor.fairy_art!=null and actor.fairy_art.visible)
 var art=actor.fairy_art
 for item in [["spar_crystal_bolt","crystal_bolt",false],["spar_crystal_veil","crystal_veil",false],["spar_crystal_bloom","crystal_bloom",true]]:
  battle._cinematic_finish_delay=0.0
  battle._event_presentation_component.animate_attack(actor,actor if item[0]=="spar_crystal_veil" else target,item[0],item[2])
  assert(str(art.animation)==item[1] and art.sprite_frames.get_frame_count(art.animation)==8)
  assert(battle._cinematic_finish_delay>=actor.fairy_action_duration(item[0],item[2]))
  assert(not art.flip_h)
  await art.animation_finished
  await process_frame
  assert(art.animation==&"left")
  print("COMPANION CLIP PASS ",item[1])
 actor.take_hit();assert(art.animation==&"hit");await art.animation_finished;await process_frame;assert(art.animation==&"left")
 actor.play_death();assert(art.animation==&"surrender")
 await battle._event_presentation_component._wait_for_gerald_surrender()
 assert(art.frame==7 and not art.is_playing() and art.animation==&"surrender")
 actor.face(Vector2.RIGHT);actor.take_hit();assert(art.animation==&"surrender")
 print("COMPANION HIT SURRENDER AND VICTORY WAIT PASS")
 battle.queue_free();for i in range(3):await process_frame
 root.get_node("AudioDirector").stop_all_audio_immediately();await create_timer(.5).timeout
 quit(0)
