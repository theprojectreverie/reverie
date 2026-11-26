extends SceneTree
const MAP="res://scenes/world/six_zone_reverie/individual_zones/zone_06_ruined_tower_standalone.tscn"
func _initialize():
 call_deferred("_run")
func _run():
 if OS.get_environment("REVERIE_E2E_DISABLE_LOCAL_SAVE")!="1":
  quit(2)
  return
 var gs=root.get_node("GameState")
 gs.quest_domain.flags["tutorial_complete"]=true
 gs.quest_domain.flags["ravienna_resurrected"]=true
 change_scene_to_file(MAP)
 await scene_changed
 for i in range(5): await process_frame
 var zone=current_scene
 var actor=zone.get_node("ReviennaEncounter")
 var player=zone.checkpoint_player
 var dialog=zone.get_node("UI/Dialogue")
 var router=zone.get_node("CombatRouter")
 player.global_position=actor.global_position+Vector2(0,120)
 actor.interact()
 assert(dialog.visible)
 dialog._show_node("warning")
 dialog._choose(dialog._node.choices[0])
 for i in range(12): await process_frame
 assert(router.active_combat!=null)
 router.active_combat._claim(false)
 await process_frame
 assert(player.input_enabled and actor.can_interact())
 actor.interact()
 dialog._show_node("warning")
 dialog._choose(dialog._node.choices[0])
 for i in range(12): await process_frame
 assert(router.active_combat!=null)
 # Test the reward-claim and ending lifecycle independently of boss balance.
 router.active_combat._claim(true)
 for i in range(5): await process_frame
 assert(gs.quest_domain.flags.get("revienna_defeated",false))
 assert(gs.quest_domain.flags.get("ravienna_ending_pending",false))
 assert(dialog.visible and dialog._dialogue_id=="revienna_victory")
 assert(actor.ending_view_active and not zone.get_node("UI/HUD").visible)
 assert(root.get_camera_2d()==zone.get_node("EndingCamera"))
 assert(not player.input_enabled and zone.get_node("ZoneUIBinding")._travel_or_combat_busy())
 dialog.close()
 assert(player.input_enabled and actor.can_interact())
 assert(not actor.ending_view_active and zone.get_node("UI/HUD").visible)
 assert(root.get_camera_2d()==player.get_node("Camera2D"))
 assert(gs.quest_domain.flags.get("ravienna_ending_pending",false))
 var gold=gs.inventory_domain.currency("gold")
 change_scene_to_file(MAP)
 await scene_changed
 for i in range(5): await process_frame
 zone=current_scene
 actor=zone.get_node("ReviennaEncounter")
 player=zone.checkpoint_player
 dialog=zone.get_node("UI/Dialogue")
 router=zone.get_node("CombatRouter")
 player.global_position=actor.global_position+Vector2(0,120)
 actor.interact()
 assert(dialog.visible and dialog._dialogue_id=="revienna_victory" and router.active_combat==null)
 dialog._show_node("end")
 dialog._choose(dialog._node.choices[0])
 assert(gs.quest_domain.flags.get("ravienna_ending_seen",false))
 assert(not gs.quest_domain.flags.get("ravienna_ending_pending",false))
 assert(player.input_enabled and not actor.can_interact())
 assert(not actor.ending_view_active and zone.get_node("UI/HUD").visible)
 assert(root.get_camera_2d()==player.get_node("Camera2D"))
 assert(gs.inventory_domain.currency("gold")==gold)
 change_scene_to_file(MAP)
 await scene_changed
 for i in range(5): await process_frame
 assert(not current_scene.get_node("ReviennaEncounter").can_interact())
 print("RAVIENNA ENDING CANCEL, REENTRY, COMPLETION, NO REPEAT BATTLE PASS")
 current_scene.queue_free()
 for i in range(3): await process_frame
 root.get_node("AudioDirector").stop_all_audio_immediately()
 await create_timer(0.35).timeout
 quit()
