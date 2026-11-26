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
 boss.play_attack()
 pose.advance(0.24)
 assert(pose.current_animation=="cast" and boss.position.is_equal_approx(home))
 for i in range(3):await process_frame
 await RenderingServer.frame_post_draw
 var img=root.get_texture().get_image()
 print("RAVIENNA THRONE CAPTURE ",img.save_png("C:/Users/quoth/Downloads/reverie_ravienna_battle_review.png"))
 boss.take_hit()
 assert(pose.current_animation=="hit")
 boss.play_death()
 pose.advance(0.8)
 assert(boss.ravienna_art.visible and boss.modulate.a==1.0 and boss.position.is_equal_approx(home))
 print("THRONE CAST, HIT AND VISIBLE SURRENDER PASS")
 battle._claim(false)
 await process_frame
 root.get_node("AudioDirector").stop_all_audio_immediately()
 await create_timer(0.35).timeout
 quit()
