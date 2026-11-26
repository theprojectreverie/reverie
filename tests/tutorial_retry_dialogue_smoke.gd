extends SceneTree
func _initialize():call_deferred("run")
func run():
 if OS.get_environment("REVERIE_E2E_DISABLE_LOCAL_SAVE")!="1":quit(2);return
 var gs=root.get_node("GameState");gs.new_game("Retry QA")
 var scene=load("res://scenes/world/tutorial_prologue/training_ground_v02.tscn").instantiate();root.add_child(scene);current_scene=scene
 await process_frame
 for i in range(3):scene.next_button.pressed.emit()
 scene.player.global_position=Vector2(0,-30);scene._open_challenge()
 for i in range(4):scene.next_button.pressed.emit()
 scene._on_practice_hit(false);scene._on_practice_hit(false);scene._on_practice_hit(true)
 scene._open_challenge();assert(scene.dialogue_stage=="challenge")
 for i in range(3):scene.next_button.pressed.emit()
 await create_timer(1.3).timeout
 var battle=scene.get_node("TutorialHUD/SparringRoot").get_child(0)
 battle.close_screen();await process_frame
 assert(battle._confirm_layer!=null)
 battle._confirm_layer.get_node("Center/Panel/Content/Actions/StayButton").pressed.emit();await process_frame
 assert(battle._confirm_layer==null and scene.sparring and not scene.player.input_enabled)
 battle.close_screen();await process_frame
 battle._confirm_layer.get_node("Center/Panel/Content/Actions/LeaveButton").pressed.emit();await process_frame
 assert(not scene.sparring and scene.player.input_enabled and scene.dummy_complete and not scene.farewell_pending and not scene.transformed)
 assert(scene.get_node("TutorialHUD/SparringRoot").get_child_count()==0 and scene.get_node("CompanionNPC").can_interact())
 assert(root.get_camera_2d()==scene.player.camera and not gs.quest_domain.flags.get("tutorial_complete",false))
 print("RETREAT CONFIRM/CANCEL AND RETURN PASS")
 scene._open_challenge();assert(scene.dialogue_stage=="retry" and not scene.player.input_enabled)
 for i in range(2):scene.next_button.pressed.emit()
 await create_timer(1.3).timeout
 battle=scene.get_node("TutorialHUD/SparringRoot").get_child(0)
 assert(scene.sparring and battle.engine.combatants.size()==2 and not battle._claimed)
 var fairy=battle._actor_for_uid(battle.engine.combatants[1].uid)
 assert(not fairy.dead and fairy.fairy_art.animation!=&"surrender")
 print("RETRY DIALOGUE AND FRESH DUEL PASS")
 battle.close_screen();await process_frame
 battle._confirm_layer.get_node("Center/Panel/Content/Actions/LeaveButton").pressed.emit();await create_timer(1.2).timeout
 scene.queue_free();for i in range(3):await process_frame
 root.get_node("AudioDirector").stop_all_audio_immediately();await create_timer(.4).timeout;quit(0)
