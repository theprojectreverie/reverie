extends SceneTree
func _initialize():
 call_deferred("_run")
func _run():
 if OS.get_environment("REVERIE_E2E_DISABLE_LOCAL_SAVE")!="1":
  quit(2)
  return
 var gs=root.get_node("GameState")
 gs.quest_domain.flags["tutorial_complete"]=true
 gs.quest_domain.flags["discovered_fast_travel_zones"]=["StandaloneVillage","StandaloneZone01","StandaloneZone02"]
 change_scene_to_file("res://scenes/world/six_zone_reverie/individual_zones/zone_03_willow_fields_standalone.tscn")
 await scene_changed
 for i in range(5): await physics_frame
 var zone=current_scene
 var player=zone.checkpoint_player
 var exit=zone.get_node("TransferPoints/ToNextZone/ToNextZoneTrigger")
 var bridge=zone.get_node("WillowObjectives/RiverCrossing")
 var ruins=zone.get_node("WillowObjectives/EasternRuins")
 assert(player.has_node("FairyCompanion"))
 assert(gs.session_domain.player_region=="willow_fields")
 assert(gs.quest_domain.quest_state("willow_crossing")=="active")
 assert(not exit._story_unlocked())
 for marker in [bridge,ruins]:
  var query=PhysicsPointQueryParameters2D.new()
  query.position=marker.global_position
  query.collision_mask=1
  assert(zone.get_world_2d().direct_space_state.intersect_point(query,1).is_empty())
 assert(gs.quest_domain.quest_target_position("willow_crossing")==bridge.global_position)
 player.global_position=ruins.global_position
 for i in range(3): await physics_frame
 assert(gs.quest_domain.quest_step_index("willow_crossing")==0)
 player.global_position=bridge.global_position
 for i in range(3): await physics_frame
 assert(gs.quest_domain.quest_step_index("willow_crossing")==1)
 assert(gs.quest_domain.quest_target_position("willow_crossing")==ruins.global_position)
 var gold=gs.inventory_domain.currency("gold")
 player.global_position=ruins.global_position
 for i in range(3): await physics_frame
 assert(gs.quest_domain.quest_state("willow_crossing")=="complete")
 assert(exit._story_unlocked())
 assert(gs.inventory_domain.currency("gold")-gold==120)
 print("WILLOW COMPANION, QUEST ORDER, MARKERS, REWARDS AND UNLOCK PASS")
 exit._on_body_entered(player)
 await scene_changed
 assert(current_scene.name==&"StandaloneZone04")
 print("ELDERWOOD TRANSITION PASS")
 if is_instance_valid(current_scene): current_scene.queue_free()
 for frame in range(3): await process_frame
 root.get_node("AudioDirector").stop_all_audio_immediately()
 await create_timer(0.35).timeout
 quit()
