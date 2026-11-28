extends SceneTree
## Disconnected guard coverage. Real retreat/cancel/retry and victory coverage
## now run in backend/api/scripts/live-spar-godot-e2e.mjs + tools/qa_live_spar.gd.
func _initialize():call_deferred("run")
func run():
 if OS.get_environment("REVERIE_E2E_DISABLE_LOCAL_SAVE")!="1":quit(2);return
 var gs=root.get_node("GameState")
 var auth=root.get_node("AuthGateway")
 if auth.is_authenticated():quit(2);return
 gs.new_game("Retry QA")
 var scene=load("res://scenes/world/tutorial_prologue/training_ground_v02.tscn").instantiate()
 root.add_child(scene)
 current_scene=scene
 await process_frame
 for i in range(3):scene.next_button.pressed.emit()
 scene._open_challenge()
 if scene.dialogue_stage!="name_companion" or scene.practice_ready or scene.player.input_enabled or scene.next_button.text!="Retry":
  push_error("Disconnected naming must require sign-in");quit(1);return
 scene.next_button.pressed.emit()
 if scene.dialogue_stage!="name_companion" or scene.practice_ready or scene.next_button.disabled:
  push_error("Disconnected retry must leave a usable prompt");quit(1);return
 if gs.quest_domain.flags.get("tutorial_complete",false) or gs.quest_domain.flags.get("tutorial_summon_seen",false):
  push_error("Disconnected tutorial must not grant progress");quit(1);return
 print("DISCONNECTED NAMING AND RETRY GUARD PASS")
 scene.queue_free()
 for i in range(3):await process_frame
 root.get_node("AudioDirector").stop_all_audio_immediately()
 await create_timer(.4).timeout
 quit(0)