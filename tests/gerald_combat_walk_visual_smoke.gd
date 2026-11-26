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
  await create_timer(2.5).timeout
  await capture("idle")
  var home: Vector2=actor.home_position
  var walk=actor.gerald_art.get_node("WalkArt")
  battle._event_presentation_component.animate_attack(actor,target,"gerald_village_flame",false)
  check(actor.gerald_walk_sequence_active and walk.visible,"Flame Strike approach starts")
  await create_timer(0.6).timeout
  check(actor.position.distance_to(home)>1.0 and walk.is_playing(),"approach moves with authored frames")
  await capture("approach")
  await create_timer(0.7).timeout
  check(not walk.visible and actor.gerald_art.animation==&"attack","attack after approach")
  check(actor.position.distance_to(home)>80.0,"approach visibly closes gap")
  await capture("strike")
  await create_timer(1.8).timeout
  check(walk.visible and actor.gerald_walk_sequence_active,"return walk starts")
  await capture("return")
  await create_timer(1.2).timeout
  check(not walk.visible and not actor.gerald_walk_sequence_active and actor.position.is_equal_approx(home),"formation restored")
  check(actor.gerald_art.animation==&"idle","idle restored")
  await capture("settled")
  battle._event_presentation_component.animate_attack(actor,target,"gerald_village_flame",false)
  actor.cancel_attack_motion()
  check(not walk.visible and not actor.gerald_walk_sequence_active and actor.position.is_equal_approx(home),"interruption restores formation")
  battle._cinematic_finish_delay=0.0
  battle._event_presentation_component.animate_attack(actor,target,"ember_lance",false)
  check(actor.gerald_art.animation==&"attack" and actor.gerald_art.sprite_frames.get_frame_count("attack")==16,"attack clip routed")
  await create_timer(1.8).timeout
  check(actor.gerald_art.animation==&"idle","attack recovers")
  battle._event_presentation_component.animate_attack(actor,target,"gerald_village_earthquake",true)
  check(actor.gerald_art.animation==&"earthquake" and actor.gerald_art.sprite_frames.get_frame_count("earthquake")==16,"ultimate clip routed")
  check(is_equal_approx(battle._cinematic_finish_delay,1.99),"full recovery reserved")
  await create_timer(1.05).timeout
  check(battle._battlefield._stage.position!=Vector2.ZERO,"earthquake shakes stage")
  await create_timer(1.05).timeout
  check(actor.gerald_art.animation==&"idle","ultimate recovers")
  check(battle._battlefield._stage.position.is_equal_approx(Vector2.ZERO),"stage restored")
 battle.call("_claim",false)
 for i in range(5):await process_frame
 check(router.active_combat==null,"retreat closes combat")
 check(player.input_enabled,"movement restored")
 check(challenge.can_interact(),"challenge can retry")
 check(not gs.quest_domain.flags.get("village_gerald_defeated",false),"retreat does not mark defeated")
 check(zone.find_child("GeraldPostVictoryStory",true,false)==null,"no backstory after retreat")
 # Exercise the victory notification without awarding actual account rewards.
 challenge.engaged=true
 root.get_node("EventBus").battle_finished.emit({"group_id":"gerald_boss_encounter","victory":true,"rewards":{}})
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
  check(story!=null,"post-victory story chapter "+str(i))
  if story==null:
   quit(1)
   return
  check(router.active_combat==null and not player.input_enabled,"story alone owns input")
  check(str(story.scene_file_path).contains("before_the_fall") if i==0 else str(story.scene_file_path).contains("gerald_boss_intro"),"chronological chapter")
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
 check(bool(gs.quest_domain.flags.get("village_gerald_backstory_seen",false)),"memories completed")
 check(not gs.quest_domain.flags.get("village_gerald_backstory_pending",false),"pending cleared")
 check(player.input_enabled,"movement restored after story")
 change_scene_to_file("res://scenes/world/village/imported_village/village_playable.tscn")
 await scene_changed
 for i in range(5):await physics_frame
 var restored=current_scene.get_node("VillageMap/GeraldBossSpawn/GeraldChallenge")
 check(not restored.can_interact() and restored.visible,"defeated state restored on scene reload")
 zone=current_scene
 check(zone.get_node("TransferPoints/ToNextZone/ExitLabel").text=="Royal Gardens","exit label restored")
 player=zone.get("checkpoint_player")
 exit_trigger=zone.get_node("TransferPoints/ToNextZone/ToNextZoneTrigger")
 exit_trigger._on_body_entered(player)
 await scene_changed
 check(current_scene.name==&"StandaloneZone01","road opens after victory")
 print("RESULT ",failures)
 quit(0 if failures.is_empty() else 1)
func capture(phase: String) -> void:
 if DisplayServer.get_name()!="headless":
  await RenderingServer.frame_post_draw
  root.get_texture().get_image().save_png("user://gerald_combat_"+phase+".png")
