extends SceneTree
func _initialize():
 call_deferred("_run")
func _run():
 if OS.get_environment("REVERIE_E2E_DISABLE_LOCAL_SAVE")!="1":
  quit(2)
  return
 var gs=root.get_node("GameState")
 gs.quest_domain.flags["tutorial_complete"]=true
 gs.quest_domain.flags["discovered_fast_travel_zones"]=["StandaloneVillage","StandaloneZone01","StandaloneZone02","StandaloneZone03","StandaloneZone04"]
 change_scene_to_file("res://scenes/world/six_zone_reverie/individual_zones/zone_05_forsaken_ruins_standalone.tscn")
 await scene_changed
 for i in range(5): await physics_frame
 var zone=current_scene
 var player=zone.checkpoint_player
 var exit=zone.get_node("TransferPoints/ToNextZone/ToNextZoneTrigger")
 var braziers=zone.get_node("RuinsBraziers").get_children()
 var tiles=zone.get_node("Zone/GroundTiles/EditableTileMap")
 assert(player.has_node("FairyCompanion"))
 assert(gs.session_domain.player_region=="forsaken_ruins")
 # Isolate preparation mechanics from combat; the courtyard regression plays the real fight.
 gs.quest_domain.flags["cassien_defeated"]=true
 gs.quest_domain.advance_quest("cassien_resurrection")
 gs.quest_domain.start_quest("forsaken_braziers")
 assert(gs.quest_domain.quest_state("forsaken_braziers")=="active")
 assert(not exit._story_unlocked())
 var gold=gs.inventory_domain.currency("gold")
 braziers[0].interact()
 assert(gs.quest_domain.quest_step_index("forsaken_braziers")==0)
 for i in range(3):
  var brazier=braziers[i]
  var pos:Vector2=brazier.global_position
  var cell:Vector2i=tiles.local_to_map(tiles.to_local(pos))
  print("BRAZIER ",i," terrain ",tiles.get_cell_source_id(cell))
  assert(tiles.get_cell_source_id(cell)>=0)
  var query=PhysicsPointQueryParameters2D.new()
  query.position=pos+Vector2(0,65)
  query.collision_mask=1
  assert(zone.get_world_2d().direct_space_state.intersect_point(query,1).is_empty())
  assert(gs.quest_domain.quest_target_position("forsaken_braziers")==pos)
  player.global_position=pos+Vector2(0,65)
  if i<2:
   braziers[i+1].interact()
   assert(gs.quest_domain.quest_step_index("forsaken_braziers")==i)
  brazier.interact()
  assert(not brazier.can_interact())
  assert(brazier.light.color.is_equal_approx(Color(1.0,0.82,0.42)))
  if i<2: assert(not exit._story_unlocked())
 assert(gs.quest_domain.quest_state("forsaken_braziers")=="complete")
 assert(gs.inventory_domain.currency("gold")-gold==180)
 assert(not exit._story_unlocked())
 print("BRAZIER INTERACTIONS, ORDER, LIGHT STATE, REWARDS PASS")
 change_scene_to_file(zone.scene_file_path)
 await scene_changed
 for i in range(5): await physics_frame
 zone=current_scene
 for brazier in zone.get_node("RuinsBraziers").get_children():
  assert(not brazier.can_interact() and brazier.light.color.is_equal_approx(Color(1.0,0.82,0.42)))
 exit=zone.get_node("TransferPoints/ToNextZone/ToNextZoneTrigger")
 assert(not exit._story_unlocked())
 var cassien=zone.get_node("CassienRitual")
 zone.checkpoint_player.global_position=cassien.global_position+Vector2(0,90)
 cassien.interact()
 var dialogue=zone.get_node("UI/Dialogue")
 assert(dialogue.visible and dialogue._dialogue_id=="cassien_ritual")
 dialogue._show_node("departure")
 dialogue._choose(dialogue._node.choices[0])
 await zone.get_node("CassienRitual").departure_finished
 assert(exit._story_unlocked())
 exit._on_body_entered(zone.checkpoint_player)
 await scene_changed
 assert(current_scene.name==&"StandaloneZone06")
 assert(current_scene.has_node("ReviennaEncounter"))
 print("PERSISTENT BRAZIERS AND REVIENNA ZONE TRANSITION PASS")
 root.get_node("AudioDirector").stop_all_audio_immediately()
 await create_timer(0.35).timeout
 quit()
