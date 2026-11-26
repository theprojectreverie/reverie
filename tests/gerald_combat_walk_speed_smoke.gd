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
 _confirm_confrontation(zone)
 for i in range(20):await process_frame
 var battle=router.active_combat
 check(battle!=null,"combat opens")
 if battle==null:
  quit(1)
  return
 check(not player.input_enabled,"movement suspended")
 check(battle.group_id=="gerald_boss_encounter","correct boss group")
 check(battle.find_child("GeraldBossIntro",true,false)==null,"no story during combat")
 for i in range(300):
  await process_frame
  if battle.engine!=null:break
 check(battle.engine!=null,"battle starts after dialogue")
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
 battle.call("_claim",false)
 for i in range(5):await process_frame
 check(router.active_combat==null,"retreat closes combat")
 check(player.input_enabled,"movement restored")
 check(challenge.can_interact(),"challenge can retry")
 check(not gs.quest_domain.flags.get("village_gerald_defeated",false),"retreat does not mark defeated")
 # Retry the live encounter and use real combat actions, not a synthetic victory.
 challenge.interact()
 _confirm_confrontation(zone)
 for i in range(20):await process_frame
 battle=router.active_combat
 check(battle!=null,"retry opens actual combat")
 if battle==null:
  quit(1)
  return
 var deadline=Time.get_ticks_msec()+90000
 while battle.engine==null and Time.get_ticks_msec()<deadline:
  await process_frame
 if battle.engine==null:
  quit(1)
  return
 var observed_boss=battle._actor_for_uid(battle.engine.combatants[1].uid)
 var observation={"approach":false,"strike":false,"return":false,"unlocked":false,"settled":false,"speed_switched":false,"return_speed_switched":false}
 var monitor=func():
  if not is_instance_valid(observed_boss) or not is_instance_valid(battle):
   return
  var walking=observed_boss.gerald_art.get_node("WalkArt")
  if observed_boss.gerald_walk_sequence_active:
   if walking.visible:
    if walking.animation in [&"walk_w",&"walk_sw",&"walk_nw"]:
     observation.approach=true
     if not observation.speed_switched:
      battle._cycle_speed()
      observation.speed_switched=is_equal_approx(battle._speed,2.4)
    elif walking.animation in [&"walk_e",&"walk_se",&"walk_ne"]:
     observation.return=true
     if not observation.return_speed_switched:
      battle._cycle_speed()
      observation.return_speed_switched=is_equal_approx(battle._speed,1.0)
   elif observed_boss.gerald_art.animation==&"attack":
    observation.strike=true
   if not battle._animating:
    observation.unlocked=true
  elif observation.return and observed_boss.position.is_equal_approx(observed_boss.home_position):
   observation.settled=true
 battle._cycle_speed()
 check(is_equal_approx(battle._speed,1.6),"battle speed cycles to 1.6x")
 process_frame.connect(monitor)
 var actions=0
 var toggled_during_enemy=false
 var ai=load("res://scripts/combat/combat_ai.gd")
 while not battle._resolved and Time.get_ticks_msec()<deadline:
  if not battle._animating and not battle.engine.finished:
   var actor=battle.engine.current_actor()
   if actor!=null and actor.team==0:
    var choice=ai.choose(battle.engine,battle.engine.current_actor_index)
    if not str(choice.skill_id).is_empty():
     await battle._session_component.execute_action(str(choice.skill_id),choice.targets)
     actions+=1
   elif actor!=null and actor.team==1 and not toggled_during_enemy:
    var before_token=battle._turn_token
    var before_hint=battle._hint_label.text
    battle._on_auto_toggled(true)
    battle._on_auto_toggled(false)
    check(battle._turn_token==before_token,"auto toggle preserves queued enemy turn")
    check(battle._hint_label.text==before_hint and before_hint.contains("prepares"),"enemy preparation warning preserved")
    toggled_during_enemy=true
  await process_frame
 process_frame.disconnect(monitor)
 print("LIVE MOVEMENT ",observation)
 check(observation.approach and observation.strike and observation.return,"actual enemy turn uses full approach and return")
 check(not observation.unlocked and observation.settled,"turn stays locked until Gerald returns")
 check(observation.speed_switched and observation.return_speed_switched,"speed changes mid-approach and return")
 check(toggled_during_enemy,"tested auto during enemy preparation")
 check(battle._resolved and battle.engine.finished and battle.engine.winner_team==0,"live victory without forced HP")
 print("ACTUAL GERALD ACTIONS ",actions," LOG ",battle.engine.log)
 if not battle._resolved or battle.engine.winner_team!=0:
  quit(1)
  return
 var boss_actor=battle._actor_for_uid(battle.engine.combatants[1].uid)
 var art=boss_actor.gerald_art
 check(boss_actor.dead and art.animation==&"defeat","surrender animation selected")
 check(art.sprite_frames.get_frame_count("defeat")==14,"all 14 authored frames")
 check(art.frame==13 and not art.is_playing(),"last kneeling frame held before result")
 check(boss_actor.modulate.a==1.0 and art.visible and art.modulate.a==1.0,"Gerald remains opaque")
 battle._claim(true)
 await process_frame
 check(bool(gs.quest_domain.flags.get("village_gerald_defeated",false)),"victory flag recorded")
 check(not challenge.can_interact() and challenge.visible,"defeated challenge disabled")
 var after_battle=zone.get_node("UI/Dialogue")
 for j in range(180):
  await process_frame
  if after_battle.visible:break
 check(after_battle.visible and after_battle._dialogue_id=="gerald_kael_after_battle","post-victory dialogue opens")
 check(router.active_combat==null and zone.find_child("GeraldPostVictoryStory",true,false)==null,"no combat or memory overlay during dialogue")
 check(not player.input_enabled,"movement locked during post-victory dialogue")
 check(fast_travel.unavailable_reason(zone,"StandaloneZone01")=="Finish Gerald's memories first","travel locked during post-victory dialogue")
 for j in range(8):
  after_battle._finish_typing()
  after_battle._on_continue()
 after_battle._finish_typing()
 check(after_battle._node_id=="09","all nine post-victory lines presented")
 after_battle._choose(after_battle._node.choices[0])
 for i in range(2):
  var story=null
  for j in range(180):
   await process_frame
   story=zone.find_child("GeraldPostVictoryStory",true,false)
   if story!=null:break
  check(story!=null,"post-victory chapter "+str(i))
  if story==null:
   quit(1)
   return
  check(router.active_combat==null and not player.input_enabled,"no overlap with combat")
  story.get_node("SkipButton").pressed.emit()
  await story.tree_exited
  if i==0:
   for j in range(180):
    await process_frame
    if after_battle.visible:break
   check(after_battle.visible and after_battle._dialogue_id=="gerald_kael_after_the_fall","interchapter dialogue opens")
   check(router.active_combat==null and zone.find_child("GeraldPostVictoryStory",true,false)==null,"chapters separated by dialogue")
   check(not player.input_enabled,"movement locked between chapters")
   check(fast_travel.unavailable_reason(zone,"StandaloneZone01")=="Finish Gerald's memories first","travel locked between chapters")
   check(root.get_node("AudioDirector").requested_music_track()=="","music paused between chapters")
   for j in range(7):
    after_battle._finish_typing()
    after_battle._on_continue()
   after_battle._finish_typing()
   check(after_battle._node_id=="08","all eight interchapter lines presented")
   after_battle._choose(after_battle._node.choices[0])
 for j in range(180):
  await process_frame
  if after_battle.visible:break
 check(after_battle.visible and after_battle._dialogue_id=="gerald_kael_farewell","closing dialogue after second chapter")
 check(router.active_combat==null and zone.find_child("GeraldPostVictoryStory",true,false)==null,"closing dialogue has no battle or cinematic overlap")
 check(not player.input_enabled,"movement locked through farewell")
 check(fast_travel.unavailable_reason(zone,"StandaloneZone01")=="Finish Gerald's memories first","travel locked through farewell")
 check(gs.quest_domain.flags.get("village_gerald_backstory_pending",false),"story remains pending until farewell")
 check(root.get_node("AudioDirector").requested_music_track()=="","tragedy music fades before farewell")
 for j in range(7):
  after_battle._finish_typing()
  after_battle._on_continue()
 after_battle._finish_typing()
 check(after_battle._node_id=="08","all eight closing lines presented")
 after_battle._choose(after_battle._node.choices[0])
 for i in range(10):await process_frame
 check(bool(gs.quest_domain.flags.get("village_gerald_backstory_seen",false)),"backstory completed after real victory")
 change_scene_to_file("res://scenes/world/village/imported_village/village_playable.tscn")
 await scene_changed
 for i in range(5):await physics_frame
 var restored=current_scene.get_node("VillageMap/GeraldBossSpawn/GeraldChallenge")
 check(not restored.can_interact() and restored.visible,"defeated state restored on scene reload")
 var kneeling=restored.get_node("FallenIdle") as AnimatedSprite2D
 check(kneeling.animation==&"defeat" and kneeling.frame==13 and not kneeling.is_playing(),"kneeling pose restored")
 check(not restored.is_in_group("world_minimap_monsters"),"no hostile marker after surrender")
 zone=current_scene
 check(zone.get_node("TransferPoints/ToNextZone/ExitLabel").text=="Royal Gardens","exit label restored")
 player=zone.get("checkpoint_player")
 exit_trigger=zone.get_node("TransferPoints/ToNextZone/ToNextZoneTrigger")
 exit_trigger._on_body_entered(player)
 await scene_changed
 check(current_scene.name==&"StandaloneZone01","road opens after victory")
 print("RESULT ",failures)
 quit(0 if failures.is_empty() else 1)
func _confirm_confrontation(zone):
 var dialogue=zone.get_node("UI/Dialogue")
 for i in range(5):
  dialogue._finish_typing()
  dialogue._on_continue()
 dialogue._finish_typing()
 dialogue._choose(dialogue._node.choices[0])
