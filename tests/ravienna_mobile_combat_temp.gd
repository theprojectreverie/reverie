extends SceneTree
const MAP="res://scenes/world/six_zone_reverie/individual_zones/zone_06_ruined_tower_standalone.tscn"
func _initialize():
 call_deferred("_run")
func _run():
 if OS.get_environment("REVERIE_E2E_DISABLE_LOCAL_SAVE")!="1":
  quit(2)
  return
 var gs=root.get_node("GameState")
 gs.quest_domain.flags["six_zone_checkpoint"]={"zone":"StandaloneVillage"}
 gs.reward_domain.apply_battle_result("gerald_boss_encounter",true)
 gs.quest_domain.flags["six_zone_checkpoint"]={"zone":"StandaloneZone01"}
 for id in ["elathra_first_audience","royal_gate_patrol","willow_crossing","elderwood_relics","forsaken_braziers"]:
  gs.roster_domain.add_party_xp(int(root.get_node("ContentDB").get_quest(id).rewards.xp))
 for id in ["royal_gate_patrol_1","royal_gate_patrol_2","cassien_encounter"]:
  gs.reward_domain.apply_battle_result(id,true)
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
 var battle=router.active_combat
 var boss
 for unit in battle.engine.combatants:
  if unit.def_id=="revienna_boss":boss=unit
 assert(boss!=null and is_equal_approx(boss.max_hp,1000.0))
 battle.engine.rng.seed=1
 var boss_actor=battle._actor_for_uid(boss.uid)
 var hud=battle._hud_component
 var bottom=battle.get_node("CombatScreenLayout/Root/CombatBottomHUD")
 assert(hud._mobile_hud and not bottom.get_node("LogPanel").visible)
 bottom.get_node("ActiveInfoPanel/InfoContent/MobileUtility").pressed.emit()
 assert(bottom.get_node("LogPanel").visible and not bottom.get_node("SkillsPanel").visible)
 await _capture("log",0.25)
 bottom.get_node("ActiveInfoPanel/InfoContent/MobileUtility").pressed.emit()
 assert(not bottom.get_node("LogPanel").visible and bottom.get_node("SkillsPanel").visible)
 await _capture("actions",0.25)
 assert(bottom.get_global_rect().end.y<=battle.get_viewport_rect().size.y+1.0,"HUD clipped")
 var utility=bottom.get_node("ActiveInfoPanel/InfoContent/MobileUtility")
 assert(utility.size.y>=78)
 assert(battle._skills_box.get_child_count()>0)
 var skill_button=battle._skills_box.get_child(0)
 assert(skill_button.size.y>=90)
 skill_button.pressed.emit()
 assert(battle._targeting_component.is_targeting() and utility.text=="Cancel target")
 utility.pressed.emit()
 assert(not battle._targeting_component.is_targeting() and utility.text=="Battle log")
 print("MOBILE HUD BOUNDS, LOG TOGGLE, SKILL TOUCH AND CANCEL PASS")
 assert(boss_actor.ravienna_art.visible and not boss_actor.visual.visible)
 var eclipse_observed={"casts":0,"impacts":0,"phases":[]}
 var pose=boss_actor.ravienna_art.get_node("PoseAnimation")
 var rig=battle._boss_presentation_rig
 pose.animation_started.connect(func(clip):
  if clip==&"eclipse":
   eclipse_observed.casts+=1
   _capture.call_deferred("eclipse_cast",0.58)
 )
 rig.impact_spawned.connect(func(_at,id):
  if id=="revienna_boss" and pose.current_animation==&"eclipse":eclipse_observed.impacts+=1
 )
 rig.phase_change_started.connect(func(id,phase,_message):
  if id=="revienna_boss":
   eclipse_observed.phases.append(phase)
   _capture.call_deferred("phase_"+str(phase),0.55)
 )
 assert(rig._phase_label_for_boss("revienna_boss",2)=="Fractured Mind")
 assert(rig._phase_label_for_boss("revienna_boss",3)=="Total Eclipse")
 var ai=load("res://scripts/combat/combat_ai.gd")
 var deadline=Time.get_ticks_msec()+90000
 var actions=0
 while not battle._resolved and Time.get_ticks_msec()<deadline:
  if not battle._animating and not battle.engine.finished:
   var current=battle.engine.current_actor()
   if current!=null and current.team==0:
    var decision=ai.choose(battle.engine,battle.engine.current_actor_index)
    await battle._session_component.execute_action(str(decision.skill_id),decision.targets)
    actions+=1
  await process_frame
 print("LIVE RESULT resolved=",battle._resolved," winner=",battle.engine.winner_team," actions=",actions)
 assert(battle._resolved and battle.engine.winner_team==0)
 assert(boss_actor.dead and boss_actor.ravienna_art.visible and boss_actor.modulate.a==1.0)
 assert(boss_actor.position.is_equal_approx(boss_actor.home_position))
 assert(not boss_actor.ravienna_art.get_node("PoseAnimation").is_playing())
 var phase_seen=false
 for line in battle.engine.log:
  if "remaining power" in str(line):phase_seen=true
 assert(phase_seen)
 print("ECLIPSE PRESENTATION ",eclipse_observed)
 assert(eclipse_observed.casts>=1 and eclipse_observed.impacts>=2 and eclipse_observed.phases==[2,3])
 print("LIVE STORY TOWER VICTORY ",actions," player actions; final phase reached")
 battle._claim(true)
 for i in range(5): await process_frame
 assert(gs.quest_domain.flags.get("revienna_defeated",false))
 assert(gs.quest_domain.flags.get("ravienna_ending_pending",false))
 assert(dialog.visible and dialog._dialogue_id=="revienna_victory")
 assert(not player.input_enabled and zone.get_node("ZoneUIBinding")._travel_or_combat_busy())
 dialog._finish_typing()
 assert(dialog.ending_landscape_layout)
 assert(dialog.get_node("DialoguePanel/ContentRow/TextColumn/Footer/ContinueButton").size.y>=84)
 await _capture("ending",0.35)
 dialog.close()
 assert(not dialog.ending_landscape_layout)
 assert(player.input_enabled and actor.can_interact())
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
 dialog._finish_typing()
 await process_frame
 assert(dialog.get_node("DialoguePanel/ContentRow/TextColumn/ChoicesBox").get_child(0).size.y>=84)
 await _capture("ending_choice",0.2)
 dialog._choose(dialog._node.choices[0])
 assert(gs.quest_domain.flags.get("ravienna_ending_seen",false))
 assert(not gs.quest_domain.flags.get("ravienna_ending_pending",false))
 assert(player.input_enabled and not actor.can_interact())
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

func _capture(name:String,delay:float):
 await create_timer(delay).timeout
 await RenderingServer.frame_post_draw
 print("CAPTURE ",name," ",root.get_texture().get_image().save_png("C:/Users/quoth/Downloads/reverie_ravienna_mobile_"+name+".png"))