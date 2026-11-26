extends SceneTree
func _initialize():call_deferred("run")
func run():
 if OS.get_environment("REVERIE_E2E_DISABLE_LOCAL_SAVE")!="1":quit(2);return
 root.get_node("GameState").new_game("Farewell QA")
 var scene=load("res://scenes/world/tutorial_prologue/training_ground_v02.tscn").instantiate();root.add_child(scene);current_scene=scene
 for i in range(5):await physics_frame
 var npc=scene.get_node("CompanionNPC");var art=npc.get_node("AnimatedSprite2D");var tiny=npc.get_node("TinyForm")
 var space=scene.get_world_2d().direct_space_state
 for side in [-1,1]:
  for dy in [-10,0,10]:
   var a=npc.global_position+Vector2(0,dy);var b=a+Vector2(side*48,0)
   assert(space.intersect_ray(PhysicsRayQueryParameters2D.create(a,b,1)).is_empty())
 print("BOTH WALK ROUTES CLEAR")
 for i in range(3):scene._accept_challenge()
 scene._open_challenge()
 for i in range(4):scene._accept_challenge()
 scene._on_practice_hit(false);scene._on_practice_hit(false);scene._on_practice_hit(true)
 scene.player.global_position=npc.global_position+Vector2(0,45)
 scene._open_challenge()
 for i in range(3):scene._accept_challenge()
 await create_timer(2.0).timeout
 var combat=scene.get_node("TutorialHUD/SparringRoot").get_child(0)
 var ai=load("res://scripts/combat/combat_ai.gd");var deadline=Time.get_ticks_msec()+45000;var actions=0
 while not combat._resolved and Time.get_ticks_msec()<deadline:
  if not combat._animating and not combat.engine.finished:
   var actor=combat.engine.current_actor()
   if actor!=null and actor.team==0:
    var decision=ai.choose(combat.engine,combat.engine.current_actor_index)
    await combat._session_component.execute_action(str(decision.skill_id),decision.targets);actions+=1
  await process_frame
 assert(combat._resolved and combat.engine.finished and combat.engine.winner_team==0)
 var fairy=combat._actor_for_uid(combat.engine.combatants[1].uid)
 assert(fairy.fairy_art.animation==&"surrender" and fairy.fairy_art.frame==7)
 print("ACTUAL DUEL VICTORY ",actions)
 combat._claim(true);await process_frame;assert(scene.farewell_pending and not scene.player.input_enabled)
 var start=npc.position
 for i in range(5):scene._accept_challenge()
 await create_timer(.45).timeout
 assert(art.animation==&"walk_left" and npc.position.distance_to(start)>10 and npc.position.distance_to(start)<48)
 assert(not scene.player.input_enabled and not scene.transformed)
 print("WALK PLAYING AND MOVING")
 await create_timer(1.65).timeout
 assert(absf(npc.position.distance_to(start)-48)<.1 and tiny.modulate.a>.95 and art.modulate.a<.01)
 print("TRANSFORMATION HANDOFF PASS")
 await create_timer(2.5).timeout
 assert(scene.dialogue_stage=="travel" and scene.player.has_node("FairyCompanion"))
 for i in range(2):scene._accept_challenge()
 await scene_changed;await process_frame
 var village=current_scene;assert(village.name==&"StandaloneVillage")
 assert(village.checkpoint_player.has_node("FairyCompanion"))
 assert(root.get_node("GameState").quest_domain.flags.get("tutorial_complete",false))
 print("VILLAGE AND FAIRY CHECKPOINT PASS")
 village.queue_free();for i in range(3):await process_frame
 root.get_node("AudioDirector").stop_all_audio_immediately();await create_timer(.5).timeout;quit(0)
