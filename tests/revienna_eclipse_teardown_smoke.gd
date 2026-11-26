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
 assert(boss_actor.ravienna_art.visible and not boss_actor.visual.visible)

 var target
 for unit in battle.engine.combatants:
  if unit.team==0:
   target=battle._actor_for_uid(unit.uid)
   break
 assert(target!=null)
 var field=battle._battlefield
 field.play_attack(boss_actor,target,"dark","ravienna_eclipse",true)
 await create_timer(0.9).timeout
 var fx=field.get_node("ReviennaEclipseEffects")
 assert(fx.get_node("Cracks/Effect0").visible and fx.get_node("Eruptions/Effect0").visible)
 var original_size=root.size
 var original_width=field.size.x
 root.size=Vector2i(844,390)
 for i in range(5):await process_frame
 assert(not is_equal_approx(field.size.x,original_width) or root.size!=original_size)
 assert(is_equal_approx(fx.get_node("Corona/Effect0").position.x,boss_actor.home_position.x))
 for i in range(3):
  var crack=fx.get_node("Cracks/Effect"+str(i))
  var eruption=fx.get_node("Eruptions/Effect"+str(i))
  assert(crack.position.is_equal_approx(eruption.position))
  assert(is_equal_approx(crack.position.x,field.size.x*(0.23+0.27*i)))
 root.size=original_size
 for i in range(5):await process_frame
 assert(is_equal_approx(fx.get_node("Corona/Effect0").position.x,boss_actor.home_position.x))
 print("ECLIPSE RESIZE AND GROUND ALIGNMENT PASS")
 var fx_ref=weakref(fx)
 var boss_ref=weakref(boss_actor)
 var battle_ref=weakref(battle)
 battle._claim(false)
 for i in range(12):await process_frame
 assert(router.active_combat==null and player.input_enabled)
 assert(fx_ref.get_ref()==null and boss_ref.get_ref()==null and battle_ref.get_ref()==null)
 await create_timer(2.3).timeout
 assert(router.active_combat==null and actor.can_interact())
 assert(not gs.quest_domain.flags.get("revienna_defeated",false))
 print("MID-ECLIPSE RETREAT, FREE EFFECTS AND NO STALE CALLBACK PASS")
 actor.interact()
 dialog._show_node("warning")
 dialog._choose(dialog._node.choices[0])
 for i in range(12):await process_frame
 var retry=router.active_combat
 assert(retry!=null)
 assert(retry._battlefield.get_node_or_null("ReviennaEclipseEffects")==null)
 var retry_boss
 for unit in retry.engine.combatants:
  if unit.def_id=="revienna_boss":retry_boss=retry._actor_for_uid(unit.uid)
 assert(retry_boss.ravienna_art.get_node("AnimatedSprite2D").animation==&"idle")
 retry._claim(false)
 for i in range(12):await process_frame
 assert(router.active_combat==null and player.input_enabled)
 print("CLEAN RECHALLENGE PASS")
 current_scene.queue_free()
 for i in range(12):await process_frame
 root.get_node("AudioDirector").stop_all_audio_immediately()
 await create_timer(0.35).timeout
 quit()
