extends SceneTree
const MAP="res://scenes/world/six_zone_reverie/individual_zones/zone_06_ruined_tower_standalone.tscn"
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
 if not failures.is_empty():
  quit(1)
  return
 print("CHAPTER Village real victory and story completed")
 for stage in [_garden, _gate, _willow, _elderwood, _ruins, _tower]:
  if not await stage.call():
   print("CHAPTER FAILED ",stage.get_method())
   quit(1)
   return
 var gs_final=root.get_node("GameState")
 for quest in ["elathra_first_audience","royal_gate_patrol","willow_crossing","elderwood_relics","forsaken_braziers","cassien_resurrection"]:
  if gs_final.quest_domain.quest_state(quest)!="complete":
   printerr("CHAPTER missing completed quest ",quest)
   quit(1)
   return
 assert(gs_final.quest_domain.flags.get("village_gerald_backstory_seen",false))
 assert(gs_final.quest_domain.flags.get("ravienna_resurrected",false))
 assert(gs_final.quest_domain.flags.get("ravienna_ending_seen",false))
 print("CHAPTER_COMPLETE PASS: all six quests, three live boss victories, memories and ending; gold=",gs_final.inventory_domain.currency("gold"))
 current_scene.queue_free()
 for f in range(3):await process_frame
 root.get_node("AudioDirector").stop_all_audio_immediately()
 # Audio mixer runs on wall time, not accelerated simulation time.
 var drain_until=Time.get_ticks_msec()+500
 while Time.get_ticks_msec()<drain_until:
  await process_frame
 quit(0)
func _confirm_confrontation(zone):
 var dialogue=zone.get_node("UI/Dialogue")
 for i in range(5):
  dialogue._finish_typing()
  dialogue._on_continue()
 dialogue._finish_typing()
 dialogue._choose(dialogue._node.choices[0])

func _garden() -> bool:
 var gs=root.get_node("GameState")
 for i in range(5):await physics_frame
 var zone=current_scene
 var player=zone.get("checkpoint_player")
 var exit=zone.get_node("TransferPoints/ToNextZone/ToNextZoneTrigger")
 var label=zone.get_node("TransferPoints/ToNextZone/ContinuationMarker/DestinationName")
 var npc=zone.get_node("Zone/RoyalGardenV3Decorations/Elathra")
 var dialogue=zone.get_node("NPCDialogueLayer/Dialogue")
 check(not exit._story_unlocked() and label.text=="Speak to Elathra first","initial quest gate locked")
 exit._on_body_entered(player)
 check(not exit.transferring,"cannot bypass by road")
 player.global_position=npc.global_position+Vector2(0,65)
 npc.interact()
 await process_frame
 check(dialogue.visible and not player.input_enabled,"Elathra dialogue locks movement")
 dialogue._choose({"next":""})
 await process_frame
 check(not dialogue.visible and player.input_enabled,"declining restores movement")
 check(not exit._story_unlocked(),"declining leaves route locked")
 npc.interact()
 await process_frame
 dialogue._choose(dialogue._node.choices[0])
 check(gs.quest_domain.quest_state("elathra_first_audience")=="active","quest accepted")
 check(not exit._story_unlocked(),"acceptance alone not enough")
 dialogue._choose(dialogue._node.choices[0])
 check(gs.quest_domain.quest_state("elathra_first_audience")=="complete","quest completed through dialogue")
 exit._on_body_entered(player)
 check(not exit.transferring,"no travel during dialogue")
 dialogue._choose(dialogue._node.choices[0])
 for i in range(5): await physics_frame
 check(player.input_enabled and exit._story_unlocked() and label.text=="Royal Gate","route unlocks after dialogue")
 exit._on_body_entered(player)
 await scene_changed
 for i in range(5): await physics_frame
 check(current_scene.name==&"StandaloneZone02","Royal Gate loaded")
 check(current_scene.get("checkpoint_player").has_node("FairyCompanion"),"companion retained")
 check(gs.quest_domain.quest_state("elathra_first_audience")=="complete","completed quest retained")
 return failures.is_empty()

func _gate() -> bool:
 var gs=root.get_node("GameState")
 for i in range(5):await physics_frame
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
 return failures.is_empty()

func _willow() -> bool:
 var gs=root.get_node("GameState")
 for i in range(5):await physics_frame
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
 return failures.is_empty()

func _elderwood() -> bool:
 var gs=root.get_node("GameState")
 for i in range(5):await physics_frame
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
 return failures.is_empty()

func _ruins() -> bool:
 var gs=root.get_node("GameState")
 for i in range(5):await physics_frame
 var zone=current_scene
 var player=zone.checkpoint_player
 var exit=zone.get_node("TransferPoints/ToNextZone/ToNextZoneTrigger")
 var cassien=zone.get_node("CassienRitual")
 var dialog=zone.get_node("UI/Dialogue")
 var braziers=zone.get_node("RuinsBraziers").get_children()
 assert(gs.quest_domain.quest_state("cassien_resurrection")=="active")
 assert(gs.quest_domain.quest_state("forsaken_braziers")=="not_started")
 assert(not exit._story_unlocked())
 for b in braziers: assert(not b.can_interact())
 player.global_position=cassien.global_position+Vector2(0,90)
 var visual=cassien.get_node("CassienVisual") as AnimatedSprite2D
 assert(visual.sprite_frames.get_frame_count(&"kneeling_idle")==8)
 assert(visual.sprite_frames.get_frame_count(&"awakening")==16)
 assert(visual.sprite_frames.get_animation_loop(&"kneeling_idle"))
 assert(not visual.sprite_frames.get_animation_loop(&"awakening"))
 assert(visual.animation==&"kneeling_idle" and visual.is_playing())
 cassien.interact()
 assert(visual.animation==&"awakening" and not player.input_enabled and not dialog.visible)
 assert(zone.get_node("ZoneUIBinding")._travel_or_combat_busy())
 assert(zone.get_meta("cassien_ritual_active",false))
 await visual.animation_finished
 await process_frame
 assert(visual.frame==15 and not visual.is_playing())
 assert(dialog.visible and not player.input_enabled)
 print("CASSIEN 8-FRAME IDLE AND 16-FRAME AWAKENING PASS")
 dialog.close()
 assert(player.input_enabled and gs.quest_domain.quest_step_index("cassien_resurrection")==0)
 assert(not zone.get_meta("cassien_ritual_active",false))
 cassien.interact()
 dialog._show_node("oath")
 dialog._choose(dialog._node.choices[0])
 await process_frame
 await process_frame
 var cassien_battle=zone.get_node("CombatRouter").active_combat
 assert(cassien_battle!=null and cassien_battle.group_id=="cassien_encounter")
 assert(gs.quest_domain.quest_state("forsaken_braziers")=="not_started")
 for i in range(300):
  await process_frame
  if cassien_battle.engine!=null:break
 assert(cassien_battle.engine!=null)
 var boss_actor=cassien_battle._actor_for_uid(cassien_battle.engine.combatants[-1].uid)
 assert(boss_actor.cassien_art!=null)
 await create_timer(2.0).timeout
 await capture("idle")
 var ai=load("res://scripts/combat/combat_ai.gd")
 var seen: Dictionary={}
 var monitor=func():
  if is_instance_valid(boss_actor):
   seen[str(boss_actor.cassien_art.animation)]=true
 process_frame.connect(monitor)
 var deadline=Time.get_ticks_msec()+85000
 var actions=0
 while not cassien_battle._resolved and Time.get_ticks_msec()<deadline:
  if not cassien_battle._animating and not cassien_battle.engine.finished:
   var actor=cassien_battle.engine.current_actor()
   if actor!=null and actor.team==0:
    var choice=ai.choose(cassien_battle.engine,cassien_battle.engine.current_actor_index)
    if not str(choice.skill_id).is_empty():
     await cassien_battle._session_component.execute_action(str(choice.skill_id),choice.targets)
     actions+=1
  await process_frame
 process_frame.disconnect(monitor)
 print("CASSIEN LIVE ACTIONS ",actions," CLIPS ",seen," LOG ",cassien_battle.engine.log)
 assert(cassien_battle._resolved and cassien_battle.engine.winner_team==0)
 assert(boss_actor.dead and boss_actor.cassien_art.animation==&"defeat" and boss_actor.cassien_art.frame==7)
 await capture("defeat")
 print("CASSIEN REAL VICTORY AND FINAL POSE PASS")
 cassien_battle._claim(true)
 await process_frame
 assert(gs.quest_domain.quest_state("forsaken_braziers")=="active")
 assert(not cassien.can_interact())
 for b in braziers:
  player.global_position=b.global_position+Vector2(0,65)
  b.interact()
 assert(gs.quest_domain.quest_state("forsaken_braziers")=="complete")
 assert(cassien.can_interact() and not exit._story_unlocked())
 player.global_position=cassien.global_position+Vector2(0,90)
 cassien.interact()
 assert(dialog._dialogue_id=="cassien_ritual")
 dialog._show_node("awakening")
 dialog.close()
 assert(not gs.quest_domain.flags.get("ravienna_resurrected",false))
 assert(not exit._story_unlocked())
 cassien.interact()
 dialog._show_node("awakening")
 assert(dialog._node.speaker=="Ravienna")
 dialog._show_node("fracture")
 dialog._show_node("departure")
 dialog._choose(dialog._node.choices[0])
 await zone.get_node("CassienRitual").departure_finished
 assert(gs.quest_domain.quest_state("cassien_resurrection")=="complete")
 assert(gs.quest_domain.flags.get("ravienna_resurrected",false))
 assert(exit._story_unlocked())
 print("CASSIEN MEETING, BRAZIER PREPARATION, CANCELLATION, RESURRECTION, ROAD PASS")
 change_scene_to_file(zone.scene_file_path)
 await scene_changed
 for i in range(5): await physics_frame
 zone=current_scene
 exit=zone.get_node("TransferPoints/ToNextZone/ToNextZoneTrigger")
 assert(exit._story_unlocked() and not zone.get_node("CassienRitual").can_interact())
 exit._on_body_entered(zone.checkpoint_player)
 await scene_changed
 for i in range(5): await physics_frame
 zone=current_scene
 assert(zone.name==&"StandaloneZone06")
 return failures.is_empty()

func _tower() -> bool:
 var gs=root.get_node("GameState")
 for i in range(5):await physics_frame
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
 var eclipse_observed={"casts":0,"impacts":0,"phases":[]}
 var pose=boss_actor.ravienna_art.get_node("PoseAnimation")
 var rig=battle._boss_presentation_rig
 pose.animation_started.connect(func(clip):
  if clip==&"eclipse":eclipse_observed.casts+=1
 )
 rig.impact_spawned.connect(func(_at,id):
  if id=="revienna_boss" and pose.current_animation==&"eclipse":eclipse_observed.impacts+=1
 )
 rig.phase_change_started.connect(func(id,phase,_message):
  if id=="revienna_boss":eclipse_observed.phases.append(phase)
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
 dialog.close()
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
 return failures.is_empty()

func capture(_phase: String) -> void:
 await process_frame
