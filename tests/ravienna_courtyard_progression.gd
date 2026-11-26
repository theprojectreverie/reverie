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
 var cassien=zone.get_node("CassienRitual")
 var courtyard=zone.get_node("RaviennaCourtyard")
 var tomb=courtyard.get_node("RaviennaStoneTomb")
 var collider=player.get_node("CollisionShape2D")
 var tiles=zone.get_node("Zone/GroundTiles/EditableTileMap")
 var space=zone.get_world_2d().direct_space_state
 var shape_query=PhysicsShapeQueryParameters2D.new()
 shape_query.shape=collider.shape
 shape_query.collision_mask=1
 assert(cassien.global_position==courtyard.get_node("EastEntrance").global_position)
 for x in [-250,-224,-192,-160,-135]:
  shape_query.transform=Transform2D(0,courtyard.to_global(Vector2(x, (x+384)*0.5-10)))
  assert(not space.intersect_shape(shape_query,8).is_empty(),"West fence gap at "+str(x))
 shape_query.transform=Transform2D(0,cassien.global_position+Vector2(0,80))
 assert(space.intersect_shape(shape_query,8).is_empty(),"Cassien approach blocked")
 print("WEST FENCE CLOSED AND CASSIEN AT EAST GATE PASS")

 assert(tomb.get_node("Artwork").texture.get_size()==Vector2(256,224))
 var probe=PhysicsPointQueryParameters2D.new()
 probe.collision_mask=1
 probe.position=tomb.global_position
 assert(not zone.get_world_2d().direct_space_state.intersect_point(probe,8).is_empty())
 probe.position=tomb.global_position+Vector2(0,90)
 assert(zone.get_world_2d().direct_space_state.intersect_point(probe,8).is_empty())
 print("TOMB IMPORT, FOOTPRINT AND APPROACH PASS")
 var dialog=zone.get_node("UI/Dialogue")
 var braziers=zone.get_node("RuinsBraziers").get_children()
 assert(gs.quest_domain.quest_state("cassien_resurrection")=="active")
 assert(gs.quest_domain.quest_state("forsaken_braziers")=="not_started")
 assert(not exit._story_unlocked())
 for b in braziers: assert(not b.can_interact())
 player.global_position=cassien.global_position+Vector2(0,90)
 cassien.interact()
 var deadline=Time.get_ticks_msec()+12000
 while not dialog.visible and Time.get_ticks_msec()<deadline:
  await process_frame
 assert(dialog.visible and not player.input_enabled)
 dialog.close()
 assert(player.input_enabled and gs.quest_domain.quest_step_index("cassien_resurrection")==0)
 cassien.interact()
 dialog._show_node("oath")
 dialog._choose(dialog._node.choices[0])
 var router=zone.get_node("CombatRouter")
 await process_frame
 await process_frame
 assert(router.active_combat!=null and router.active_combat.group_id=="cassien_encounter")
 assert(not player.input_enabled and not exit._story_unlocked())
 assert(gs.quest_domain.quest_state("forsaken_braziers")=="not_started")
 router.active_combat._claim(false)
 await process_frame
 assert(player.input_enabled and gs.quest_domain.quest_step_index("cassien_resurrection")==0)
 cassien.interact()
 dialog._show_node("oath")
 dialog._choose(dialog._node.choices[0])
 await process_frame
 await process_frame
 var battle=router.active_combat
 assert(battle!=null)
 var boss
 for unit in battle.engine.combatants:
  if unit.def_id=="cassien_boss":
   boss=battle._actor_for_uid(unit.uid)
 assert(boss!=null and boss.cassien_art.visible and not boss.visual.visible)
 var battle_deadline=Time.get_ticks_msec()+45000
 var ai=load("res://scripts/combat/combat_ai.gd")
 while not battle._resolved and Time.get_ticks_msec()<battle_deadline:
  if not battle._animating and not battle.engine.finished:
   var actor=battle.engine.current_actor()
   if actor!=null and actor.team==0:
    var decision=ai.choose(battle.engine,battle.engine.current_actor_index)
    await battle._session_component.execute_action(str(decision.skill_id),decision.targets)
  await process_frame
 assert(battle._resolved and battle.engine.winner_team==0)
 assert(boss.dead and boss.cassien_art.animation==&"defeat")
 battle._claim(true)
 await process_frame
 assert(gs.quest_domain.flags.get("cassien_defeated",false))
 assert(player.input_enabled)
 print("CASSIEN REAL BATTLE, ART, RETREAT, RETRY AND VICTORY PASS")

 assert(gs.quest_domain.quest_state("forsaken_braziers")=="active")
 assert(not cassien.can_interact())
 for b in braziers:
  player.global_position=b.global_position+Vector2(0,65)
  b.interact()
 assert(gs.quest_domain.quest_state("forsaken_braziers")=="complete")
 assert(cassien.can_interact() and not exit._story_unlocked())
 assert(cassien.global_position==zone.get_node("CassienTombPosition").global_position)
 assert(gs.quest_domain.quest_target_position("cassien_resurrection")==cassien.global_position)
 await physics_frame
 shape_query.transform=Transform2D(0,cassien.global_position+Vector2(0,80))
 assert(space.intersect_shape(shape_query,8).is_empty(),"Ritual approach blocked")
 var east_route=[Vector2(330,260),Vector2(330,190),Vector2(192,96),Vector2(90,110),Vector2(0,95)]
 for i in range(east_route.size()-1):
  for j in range(25):
   var point:Vector2=courtyard.to_global(east_route[i].lerp(east_route[i+1],float(j)/24))
   assert(point.distance_to(cassien.global_position)>cassien.interaction_radius)
   shape_query.transform=Transform2D(0,point+Vector2(0,-10))
   assert(space.intersect_shape(shape_query,8).is_empty())
 print("TOMB-SIDE RITUAL POSITION AND INDEPENDENT EAST ENTRANCE PASS")
 player.global_position=cassien.global_position+Vector2(0,90)
 cassien.interact()
 assert(dialog._dialogue_id=="cassien_ritual")
 assert(cassien.ritual_view_active and not zone.get_node("UI/HUD").visible)
 assert(zone.get_viewport().get_camera_2d()==cassien.ritual_camera)
 assert(is_equal_approx(dialog.get_node("Dim").color.a,0.12))
 dialog._show_node("awakening")
 assert(cassien.tomb_animation.current_animation=="awakening")
 cassien.tomb_animation.advance(0.55)
 assert(not tomb.get_node("Artwork").modulate.is_equal_approx(Color.WHITE))
 dialog.close()
 assert(tomb.get_node("Artwork").modulate.is_equal_approx(Color.WHITE))
 assert(not cassien.ritual_view_active and zone.get_node("UI/HUD").visible)
 assert(zone.get_viewport().get_camera_2d()==player.get_node("Camera2D"))
 assert(is_equal_approx(dialog.get_node("Dim").color.a,0.64))
 assert(not gs.quest_domain.flags.get("ravienna_resurrected",false))
 assert(not exit._story_unlocked())
 cassien.interact()
 dialog._show_node("awakening")
 assert(dialog._node.speaker=="Ravienna")
 dialog._show_node("fracture")
 assert(cassien.tomb_animation.current_animation=="fracture")
 dialog._show_node("departure")
 dialog._choose(dialog._node.choices[0])
 await zone.get_node("CassienRitual").departure_finished
 assert(gs.quest_domain.quest_state("cassien_resurrection")=="complete")
 assert(gs.quest_domain.flags.get("ravienna_resurrected",false))
 assert(not cassien.ritual_view_active and zone.get_node("UI/HUD").visible)
 assert(zone.get_viewport().get_camera_2d()==player.get_node("Camera2D"))
 print("RITUAL CAMERA, HUD AND DIALOGUE RESTORATION PASS")
 assert(exit._story_unlocked())
 print("CASSIEN MEETING, BRAZIER PREPARATION, CANCELLATION, RESURRECTION, ROAD PASS")
 change_scene_to_file(zone.scene_file_path)
 await scene_changed
 for i in range(5): await physics_frame
 zone=current_scene
 exit=zone.get_node("TransferPoints/ToNextZone/ToNextZoneTrigger")
 assert(exit._story_unlocked() and not zone.get_node("CassienRitual").can_interact())
 assert(zone.get_node("CassienRitual").global_position==zone.get_node("CassienTombPosition").global_position)
 exit._on_body_entered(zone.checkpoint_player)
 await scene_changed
 for i in range(5): await physics_frame
 zone=current_scene
 assert(zone.name==&"StandaloneZone06")
 var ravienna=zone.get_node("ReviennaEncounter")
 player=zone.checkpoint_player
 player.global_position=ravienna.global_position+Vector2(0,120)
 ravienna.interact()
 dialog=zone.get_node("UI/Dialogue")
 assert(dialog.visible and dialog._dialogue_id=="revienna_challenge")
 dialog._show_node("reply")
 assert("Cassien and I brought you back" in dialog._node.text)
 dialog._show_node("warning")
 dialog._choose(dialog._node.choices[0])
 for i in range(20): await process_frame
 assert(zone.get_node("CombatRouter").active_combat!=null)
 print("PERSISTENT RITUAL, RAVIENNA DIALOGUE AND BOSS LAUNCH PASS")
 zone.get_node("CombatRouter").active_combat._claim(false)
 await process_frame
 root.get_node("AudioDirector").stop_all_audio_immediately()
 await create_timer(0.35).timeout
 quit()
