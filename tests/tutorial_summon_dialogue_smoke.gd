extends SceneTree
func _initialize() -> void:
 call_deferred("run")
func run() -> void:
 assert(OS.get_environment("REVERIE_E2E_DISABLE_LOCAL_SAVE") == "1")
 var gs = root.get_node("GameState")
 var auth = root.get_node("AuthGateway")
 assert(not auth.is_authenticated())
 var training = load("res://scenes/world/tutorial_prologue/training_ground_v02.tscn").instantiate()
 root.add_child(training)
 current_scene = training
 await process_frame
 assert(root.get_node("ContentDB").get_character("kael_legendary") != null)
 assert(training.DIALOGUES["summon"].size() == 6)
 training.companion_name = "Astra"
 training._show_dialogue("summon")
 assert(not training.player.input_enabled and training.dialogue_stage == "summon")
 assert(training.speaker.text == "Astra")
 for i in range(training.DIALOGUES["summon"].size() - 1):
  training.next_button.pressed.emit()
 assert(training.next_button.text == "Perform free summon")
 var before = gs.inventory_domain.currency("crystals")
 training.next_button.pressed.emit()
 assert(training.dialogue_stage == "summon" and not training._tutorial_summon_busy)
 assert(not gs.quest_domain.flags.get("tutorial_summon_seen", false))
 assert(gs.inventory_domain.currency("crystals") == before)
 print("COMPANION LESSON AND DISCONNECTED RETRY PASS")
 training.queue_free()
 await process_frame
 root.get_node("AudioDirector").stop_all_audio_immediately()
 await create_timer(0.4).timeout
 quit()