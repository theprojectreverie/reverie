extends SceneTree
var failures: Array[String]=[]
func _initialize():
 call_deferred("_run")
func check(ok:bool, label:String):
 print("CHECK ",label," = ",ok)
 if not ok:failures.append(label)
func _run():
 if OS.get_environment("REVERIE_E2E_DISABLE_LOCAL_SAVE")!="1":
  quit(2)
  return
 var gs=root.get_node("GameState")
 gs.quest_domain.flags["tutorial_complete"]=true
 gs.quest_domain.flags.erase("village_gerald_defeated")
 gs.quest_domain.flags.erase("village_gerald_backstory_pending")
 gs.quest_domain.flags.erase("village_gerald_backstory_seen")
 gs.quest_domain.flags.erase("discovered_fast_travel_zones")
 gs.quest_domain.flags["six_zone_checkpoint"]={"zone":"StandaloneVillage","x":-2090.0,"y":112.0}
 change_scene_to_file("res://scenes/world/village/imported_village/village_playable.tscn")
 await scene_changed
 for i in range(5):await physics_frame
 var zone=current_scene
 var player=zone.get("checkpoint_player")
 var challenge=zone.get_node("VillageMap/GeraldBossSpawn/GeraldChallenge")
 var router=zone.get_node("CombatRouter")
 check(player.avatar_id=="kael","Kael playable")
 check(player.has_node("FairyCompanion"),"fairy companion present")
 check(challenge.can_interact(),"challenge available")
 var exit_trigger=zone.get_node("TransferPoints/ToNextZone/ToNextZoneTrigger")
 var exit_label=zone.get_node("TransferPoints/ToNextZone/ExitLabel")
 var fast_travel=load("res://scripts/world/six_zone_reverie/fast_travel.gd")
 exit_trigger._on_body_entered(player)
 check(not exit_trigger.transferring,"road locked before victory")
 check(exit_label.text=="Defeat Gerald first","locked exit label")
 check(fast_travel.unavailable_reason(zone,"StandaloneZone01")=="Defeat Gerald first","fast travel locked")
 challenge.interact()
 check(router.active_combat==null,"cannot challenge from far away")
 player.global_position=challenge.global_position+Vector2(0,60)
 await physics_frame
 challenge.interact()
 var dialogue=zone.get_node("UI/Dialogue")
 check(dialogue.visible and router.active_combat==null,"dialogue before combat")
 check(not player.input_enabled,"dialogue suspends movement")
 dialogue.close()
 check(challenge.can_interact() and player.input_enabled,"cancel dialogue restores movement")
 challenge.interact()
 for i in range(5):
  dialogue._finish_typing()
  dialogue._on_continue()
 dialogue._finish_typing()
 check(dialogue._node_id=="06","final confrontation choice")
 dialogue._choose(dialogue._node.choices[0])
 for i in range(20):await process_frame
 var battle=router.active_combat
 check(battle!=null,"combat opens")
 if battle==null:
  quit(1)
  return
 check(not player.input_enabled,"movement suspended")
 check(battle.group_id=="gerald_boss_encounter","correct boss group")
 check(battle.find_child("GeraldBossIntro",true,false)==null,"no backstory during combat")
 for i in range(300):
  await process_frame
  if battle.engine!=null:break
 check(battle.engine!=null,"battle starts directly after dialogue")
 if battle.engine!=null:
  var players=[]
  var enemies=[]
  for unit in battle.engine.combatants:
   if unit.team==0:players.append(unit.def_id)
   else:enemies.append(unit.def_id)
  print("PARTY ",players," ENEMIES ",enemies)
  check(players==["kael"],"sole Kael combat party")
  check(enemies==["gerald_boss"],"Gerald opponent")
  check(is_equal_approx(battle.engine.combatants[1].max_hp,330.0),"village balance applied in live battle")
  var boss=battle.engine.combatants[1]
  var kael=battle.engine.combatants[0]
  var actor=battle._actor_for_uid(boss.uid)
  var target=battle._actor_for_uid(kael.uid)
  check(actor.gerald_art.visible and not actor.visual.visible,"authored boss replaces placeholder")
  check(boss.ultimate=="gerald_village_earthquake","boss ultimate assigned")
  var walk=actor.gerald_art.get_node("WalkArt")
  battle._event_presentation_component.animate_attack(actor,target,"gerald_village_flame",false)
  await create_timer(0.45).timeout
  check(actor.gerald_walk_sequence_active and walk.visible,"retreat starts during active walk")
  var actor_ref=weakref(actor)
  var battle_ref=weakref(battle)
  battle.call("_claim",false)
  for i in range(10):await process_frame
  check(router.active_combat==null and player.input_enabled,"mid-walk retreat restores exploration")
  check(actor_ref.get_ref()==null and battle_ref.get_ref()==null,"old actor and combat screen released")
  await create_timer(4.5).timeout
  check(router.active_combat==null and challenge.can_interact(),"no delayed callback reopens combat")
  challenge.interact()
  for i in range(5):
   dialogue._finish_typing()
   dialogue._on_continue()
  dialogue._finish_typing()
  dialogue._choose(dialogue._node.choices[0])
  for i in range(180):
   await physics_frame
   if router.active_combat!=null:break
  check(router.active_combat!=null,"rechallenge after interrupted walk")
  if router.active_combat!=null:
   var retry=router.active_combat
   for i in range(300):
    await process_frame
    if retry.engine!=null:break
   var retry_actor=retry._actor_for_uid(retry.engine.combatants[1].uid)
   check(not retry_actor.gerald_walk_sequence_active and retry_actor.gerald_art.self_modulate.a==1.0,"fresh combat starts with intact idle art")
   retry.call("_claim",false)
   for i in range(10):await process_frame
  check(router.active_combat==null and player.input_enabled,"second retreat succeeds")
  check(not gs.quest_domain.flags.get("village_gerald_defeated",false),"retreat does not affect progression")
 print("RESULT ",failures)
 quit(0 if failures.is_empty() else 1)
