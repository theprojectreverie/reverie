extends SceneTree
func _initialize():
 call_deferred("_run")
func _run():
 if OS.get_environment("REVERIE_E2E_DISABLE_LOCAL_SAVE")!="1":
  quit(2)
  return
 var gs=root.get_node("GameState")
 gs.quest_domain.flags["tutorial_complete"]=true
 gs.quest_domain.flags["discovered_fast_travel_zones"]=["StandaloneVillage","StandaloneZone01"]
 change_scene_to_file("res://scenes/world/six_zone_reverie/individual_zones/zone_02_royal_gate_standalone.tscn")
 await scene_changed
 for i in range(5): await physics_frame
 var zone=current_scene
 var player=zone.checkpoint_player
 var exit=zone.get_node("TransferPoints/ToNextZone/ToNextZoneTrigger")
 var patrol=zone.get_node("RoyalGatePatrol")
 assert(gs.quest_domain.quest_state("royal_gate_patrol")=="active")
 assert(not exit._story_unlocked())
 var gold=gs.inventory_domain.currency("gold")
 var a=patrol.get_node("Crownling01")
 var b=patrol.get_node("Crownling02")
 for mob in [a,b]:
  var query=PhysicsPointQueryParameters2D.new()
  query.position=mob.global_position
  query.collision_mask=1
  assert(zone.get_world_2d().direct_space_state.intersect_point(query,1).is_empty())
 assert(gs.quest_domain.quest_target_position("royal_gate_patrol")==a.global_position)
 a.receive_world_hit(120.0)
 assert(a.defeated and not exit._story_unlocked())
 a.receive_world_hit(120.0)
 assert(not exit._story_unlocked())
 b.receive_world_hit(120.0)
 assert(gs.quest_domain.quest_state("royal_gate_patrol")=="complete")
 assert(exit._story_unlocked())
 assert(gs.inventory_domain.currency("gold")-gold==162)
 print("PATROL QUEST, CLEAR SPAWNS, TRACKING, REWARDS AND UNLOCK PASS")
 exit._on_body_entered(player)
 await scene_changed
 assert(current_scene.name==&"StandaloneZone03")
 print("WILLOW FIELDS TRANSITION PASS")
 if is_instance_valid(current_scene): current_scene.queue_free()
 for frame in range(3): await process_frame
 root.get_node("AudioDirector").stop_all_audio_immediately()
 await create_timer(0.35).timeout
 quit()
