extends SceneTree
func _initialize():call_deferred("_run")
func _run():
 if OS.get_environment("REVERIE_E2E_DISABLE_LOCAL_SAVE")!="1":
  quit(2)
  return
 var factory=load("res://scripts/combat/combat_factory.gd")
 var field=load("res://scenes/ui/battlefield.tscn").instantiate()
 root.add_child(field)
 field.size=Vector2(1200,400)
 var unit=factory.build_from_character(CharacterInstance.create("elathra","audit_elathra"))
 var enemies=factory.enemy_units("cassien_encounter")
 field.setup([unit],enemies)
 for i in range(5):await process_frame
 var a=field.actor_for_uid(unit.uid)
 var e=field.actor_for_uid(enemies[0].uid)
 assert(a.elathra_art.visible and not a.visual.visible)
 assert(a.elathra_art.sprite_frames.get_frame_count("idle")==5)
 assert(a.home_position.x<e.home_position.x)
 for skill in unit.skills+[unit.ultimate]:
  a.cancel_attack_motion()
  field.play_attack(a,e,"dark",skill,skill==unit.ultimate)
  assert(a.elathra_art.get_node("PoseAnimation").current_animation=="cast")
  await create_timer(.85).timeout
  assert(a.position.is_equal_approx(a.home_position))
 a.take_hit()
 assert(a.elathra_art.get_node("PoseAnimation").current_animation=="hit")
 a.play_victory()
 assert(a.elathra_art.modulate==Color.WHITE)
 if DisplayServer.get_name()!="headless":
  await RenderingServer.frame_post_draw
  print("CAPTURE ",root.get_texture().get_image().save_png("C:/Users/quoth/Downloads/reverie_elathra_battle_review.png"))
 a.play_death()
 assert(a.dead and a.elathra_art.get_node("PoseAnimation").current_animation=="defeat")
 await create_timer(.7).timeout
 assert(a.elathra_art.modulate.a<.5)
 field.queue_free()
 await process_frame
 print("ELATHRA AUTHORED IDLE, THREE SKILL ROUTES, HIT, VICTORY AND DEFEAT PASS")
 var gs=root.get_node("GameState")
 gs.quest_domain.flags["tutorial_complete"]=true
 gs.quest_domain.flags["village_gerald_defeated"]=true
 change_scene_to_file("res://scenes/world/six_zone_reverie/individual_zones/zone_05_forsaken_ruins_standalone.tscn")
 await scene_changed
 for i in range(8):await process_frame
 var p=current_scene.checkpoint_player
 assert(p.avatar_component.set_avatar("gerald"))
 var before=p.visual.character_art_report()
 assert(not p.avatar_component.set_avatar("nyx"))
 assert(p.avatar_id=="gerald" and p.visual.character_art_report()==before and p.visual._sprite.visible)
 print("INVALID AVATAR SWITCH PRESERVES GERALD PASS")
 current_scene.queue_free()
 for i in range(3):await process_frame
 root.get_node("AudioDirector").stop_all_audio_immediately()
 await create_timer(.35).timeout
 quit()
