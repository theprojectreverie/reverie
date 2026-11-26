extends SceneTree
func _initialize():
 call_deferred("_run")
func _run():
 if OS.get_environment("REVERIE_E2E_DISABLE_LOCAL_SAVE")!="1":
  quit(2)
  return
 var gs=root.get_node("GameState")
 gs.quest_domain.flags["tutorial_complete"]=true
 gs.quest_domain.flags["discovered_fast_travel_zones"]=["StandaloneVillage","StandaloneZone01","StandaloneZone02","StandaloneZone03"]
 change_scene_to_file("res://scenes/world/six_zone_reverie/individual_zones/zone_04_elderwood_grove_standalone.tscn")
 await scene_changed
 for i in range(5): await physics_frame
 var zone=current_scene
 var player=zone.checkpoint_player
 var exit=zone.get_node("TransferPoints/ToNextZone/ToNextZoneTrigger")
 var a=zone.get_node("ElderwoodRelics/BrokenMemorial")
 var b=zone.get_node("ElderwoodRelics/WeatheredPillar")
 var tiles=zone.get_node("Zone/GroundTiles/EditableTileMap")
 assert(player.has_node("FairyCompanion"))
 assert(gs.session_domain.player_region=="elderwood_grove")
 assert(gs.quest_domain.quest_state("elderwood_relics")=="active")
 assert(not exit._story_unlocked())
 assert(a.can_interact() and not b.can_interact())
 for relic in [a,b]:
  var pos: Vector2=relic.global_position
  var cell: Vector2i=tiles.local_to_map(tiles.to_local(pos))
  print("RELIC ",relic.name," terrain source ",tiles.get_cell_source_id(cell)," sprite ",relic.get_node("Artwork").texture.get_size())
  assert(tiles.get_cell_source_id(cell)>=0)
  var query=PhysicsPointQueryParameters2D.new()
  query.position=pos+Vector2(0,60)
  query.collision_mask=1
  assert(zone.get_world_2d().direct_space_state.intersect_point(query,1).is_empty())
 assert(gs.quest_domain.quest_target_position("elderwood_relics")==a.global_position)
 a.interact()
 assert(gs.quest_domain.quest_step_index("elderwood_relics")==0)
 player.global_position=b.global_position+Vector2(0,60)
 b.interact()
 assert(gs.quest_domain.quest_step_index("elderwood_relics")==0)
 player.global_position=a.global_position+Vector2(0,60)
 a.interact()
 assert(gs.quest_domain.quest_step_index("elderwood_relics")==1)
 assert(not a.can_interact() and b.can_interact())
 assert(gs.quest_domain.quest_target_position("elderwood_relics")==b.global_position)
 var gold=gs.inventory_domain.currency("gold")
 player.global_position=b.global_position+Vector2(0,60)
 b.interact()
 assert(gs.quest_domain.quest_state("elderwood_relics")=="complete")
 assert(exit._story_unlocked())
 assert(gs.inventory_domain.currency("gold")-gold==140)
 b.interact()
 assert(gs.inventory_domain.currency("gold")-gold==140)
 print("ELDERWOOD RELIC ORDER, DISTANCE, REWARDS, TERRAIN, REGION AND COMPANION PASS")
 exit._on_body_entered(player)
 await scene_changed
 assert(current_scene.name==&"StandaloneZone05")
 print("FORSAKEN RUINS TRANSITION PASS")
 if is_instance_valid(current_scene): current_scene.queue_free()
 for frame in range(3): await process_frame
 root.get_node("AudioDirector").stop_all_audio_immediately()
 await create_timer(0.35).timeout
 quit()
