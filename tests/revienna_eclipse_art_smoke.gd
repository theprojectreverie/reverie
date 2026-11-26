extends SceneTree
func _initialize():
 call_deferred("_run")
func _run():
 if OS.get_environment("REVERIE_E2E_DISABLE_LOCAL_SAVE")!="1":
  quit(2)
  return
 var gs=root.get_node("GameState")
 gs.quest_domain.flags["tutorial_complete"]=true
 gs.quest_domain.flags["ravienna_resurrected"]=true
 change_scene_to_file("res://scenes/world/six_zone_reverie/individual_zones/zone_06_ruined_tower_standalone.tscn")
 await scene_changed
 for i in range(5): await process_frame
 var zone=current_scene
 var actor=zone.get_node("ReviennaEncounter")
 zone.checkpoint_player.global_position=actor.global_position+Vector2(0,120)
 actor.interact()
 var dialog=zone.get_node("UI/Dialogue")
 dialog._show_node("warning")
 dialog._choose(dialog._node.choices[0])
 for i in range(20): await process_frame
 var battle=zone.get_node("CombatRouter").active_combat
 assert(battle!=null)
 var boss:Node2D
 for unit in battle.engine.combatants:
  if unit.def_id=="revienna_boss":boss=battle._actor_for_uid(unit.uid)
 assert(boss.ravienna_art.visible and not boss.visual.visible)
 var sprite=boss.ravienna_art.get_node("AnimatedSprite2D")
 assert(sprite.sprite_frames.get_frame_count("idle")==8)
 var pose=boss.ravienna_art.get_node("PoseAnimation")
 var home=boss.home_position

 for clip in ["shadow_lash","corruption_bolt","soul_drain","hollow_wail","ravienna_eclipse"]:
  var expected=16 if clip=="ravienna_eclipse" else 12 if clip in ["soul_drain","hollow_wail"] else 8
  assert(sprite.sprite_frames.get_frame_count(clip)==expected)
  assert(boss.play_revienna_action(clip))
  for i in range(18): await process_frame
  assert(sprite.animation==clip and sprite.frame>0)
  await sprite.animation_finished
  await process_frame
  print("CLIP ",clip," FINISHED ",sprite.animation," position ",boss.position," home ",boss.home_position," old ",home)
  assert(sprite.animation=="idle" and boss.position.is_equal_approx(boss.home_position))
 var target
 for unit in battle.engine.combatants:
  if unit.team==0:
   target=battle._actor_for_uid(unit.uid)
   break
 assert(target!=null)
 battle._battlefield.play_attack(boss,target,"dark","ravienna_eclipse",true)
 await create_timer(1.28).timeout
 var fx=battle._battlefield.get_node("ReviennaEclipseEffects")
 assert(fx!=null and sprite.animation=="ravienna_eclipse")
 assert(fx.get_node("Cracks/Effect0").visible and fx.get_node("Eruptions/Effect1").visible and fx.get_node("Corona/Effect0").visible)
 assert(fx.get_node("Cracks/Effect0").frame>=6)
 await RenderingServer.frame_post_draw
 var img=root.get_texture().get_image()
 print("ECLIPSE CAPTURE ",img.save_png("C:/Users/quoth/Downloads/reverie_eclipse_verdict_review.png"))
 await create_timer(1.0).timeout
 assert(not is_instance_valid(fx) and sprite.animation=="idle")
 print("FIVE ATTACK CLIPS, ECLIPSE LAYERS, CLEANUP AND RETURN TO IDLE PASS")
 battle._claim(false)
 await process_frame
 root.get_node("AudioDirector").stop_all_audio_immediately()
 await create_timer(0.35).timeout
 quit()
