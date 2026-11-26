extends SceneTree
func _initialize():
 call_deferred("run")
func run():
 if OS.get_environment("REVERIE_E2E_DISABLE_LOCAL_SAVE")!="1":
  quit(2)
  return
 var gs=root.get_node("GameState")
 gs.new_game("Cassien QA")
 gs.quest_domain.flags["tutorial_complete"]=true
 gs.quest_domain.flags["discovered_fast_travel_zones"]=["StandaloneVillage","StandaloneZone01","StandaloneZone02","StandaloneZone03","StandaloneZone04"]
 change_scene_to_file("res://scenes/world/six_zone_reverie/individual_zones/zone_05_forsaken_ruins_standalone.tscn")
 await scene_changed
 for i in range(5): await physics_frame
 var zone=current_scene
 var player=zone.checkpoint_player
 var cassien=zone.get_node("CassienRitual")
 var dialog=zone.get_node("UI/Dialogue")
 var router=zone.get_node("CombatRouter")
 player.global_position=cassien.global_position+Vector2(0,90)
 cassien.interact()
 await cassien.cassien_visual.animation_finished
 await process_frame
 dialog._show_node("oath")
 dialog._choose(dialog._node.choices[0])
 await process_frame
 await process_frame
 var battle=router.active_combat
 assert(battle!=null and not player.input_enabled)
 battle._turn_token+=1
 var boss=battle.engine.combatants[-1]
 boss.hp=100.0
 boss.energy=100.0
 var old_actor=battle._actor_for_uid(boss.uid)
 old_actor.play_cassien_action("cassien_crimson_requiem",true)
 await battle._result_component.finish_battle(false)
 battle._result_component.retry()
 await process_frame
 var fresh=battle.engine.combatants[-1]
 var new_actor=battle._actor_for_uid(fresh.uid)
 assert(fresh.hp==fresh.max_hp and fresh.energy==0.0 and not battle._resolved)
 assert(new_actor!=old_actor and new_actor.cassien_art.animation==&"idle")
 assert(not player.input_enabled and gs.quest_domain.quest_step_index("cassien_resurrection")==0)
 print("CASSIEN RETRY RESET PASS")
 battle._claim(false)
 await process_frame
 await process_frame
 assert(router.active_combat==null and player.input_enabled and not cassien.engaged)
 assert(gs.quest_domain.quest_step_index("cassien_resurrection")==0 and gs.quest_domain.quest_state("forsaken_braziers")=="not_started")
 assert(cassien.can_interact() and not gs.quest_domain.flags.get("cassien_defeated",false))
 print("CASSIEN RETREAT NO PROGRESSION PASS")
 cassien.interact()
 assert(dialog.visible)
 dialog._show_node("oath")
 dialog._choose(dialog._node.choices[0])
 await process_frame
 await process_frame
 assert(router.active_combat!=null and router.active_combat.engine.combatants[-1].hp==fresh.max_hp)
 router.active_combat._claim(false)
 await process_frame
 await process_frame
 print("CASSIEN RECHALLENGE PASS")
 zone.queue_free()
 for i in range(3): await process_frame
 await create_timer(2.0).timeout
 quit(0)
