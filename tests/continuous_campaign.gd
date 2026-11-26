extends SceneTree
func _initialize():call_deferred("run")
func fail(message:String):
 push_error("FULL TUTORIAL FAIL: "+message);quit(1)
func move_input(v:Vector2):
 for a in ["move_left","move_right","move_up","move_down"]:Input.action_release(a)
 if v.x<-.05:Input.action_press("move_left",-v.x)
 if v.x>.05:Input.action_press("move_right",v.x)
 if v.y<-.05:Input.action_press("move_up",-v.y)
 if v.y>.05:Input.action_press("move_down",v.y)
func walk_to(player,goal:Vector2,radius:float=16.0)->bool:
 var end=Time.get_ticks_msec()+12000
 while is_instance_valid(player) and player.global_position.distance_to(goal)>radius and Time.get_ticks_msec()<end:
  move_input((goal-player.global_position).normalized());await physics_frame
 move_input(Vector2.ZERO)
 if not is_instance_valid(player):return true
 for i in range(8):await physics_frame
 return player.global_position.distance_to(goal)<radius+12
func press_action(action:String):
 var event=InputEventAction.new();event.action=action;event.pressed=true;Input.parse_input_event(event)
 await process_frame
 event=InputEventAction.new();event.action=action;event.pressed=false;Input.parse_input_event(event)
func run():
 if OS.get_environment("REVERIE_E2E_DISABLE_LOCAL_SAVE")!="1":quit(2);return
 var gs=root.get_node("GameState");gs.new_game("Full Tutorial QA")
 var main=load("res://scenes/main.tscn").instantiate();root.add_child(main);current_scene=main
 for i in range(4):await process_frame
 assert(main.get_node("TitleScreen/NewJourneyButton")!=null)
 # Authentication is intentionally not exercised by this offline gameplay test.
 main.startup_flow._prepare_new_journey();main.startup_flow._launch_new_journey()
 await process_frame
 var intro=main.get_node("OpeningCinematic");var playback=intro.playback_component
 var total=playback.shots.size();assert(total>0)
 for i in range(total):
  assert(playback.shot_index==i)
  var shot=playback.current_shot();assert(intro.get_node("Artwork").texture.resource_path==str(shot.image));assert(intro.get_node("Caption").text==str(shot.caption) and not str(shot.caption).is_empty())
  await create_timer(.42).timeout
  assert(intro.get_node("Artwork").modulate.a>.95)
  var click=InputEventMouseButton.new();click.button_index=MOUSE_BUTTON_LEFT;click.pressed=true;click.position=Vector2(300,240);Input.parse_input_event(click)
  await process_frame
  if i<total-1:await create_timer(.38).timeout
 await scene_changed;await process_frame
 print("OPENING ALL SHOTS PASS ",total)
 var bedroom=current_scene;assert(bedroom.name==&"KaelDiamondBedroom")
 var kael=bedroom.get_node("Kael");print("BEDROOM SPAWN ",kael.position)
 if not await walk_to(kael,Vector2(145,75)):fail("bedroom route 1 "+str(kael.position));return
 if not await walk_to(kael,Vector2(-5,120)):fail("bedroom route 2 "+str(kael.position));return
 move_input(Vector2.DOWN)
 var limit=Time.get_ticks_msec()+6000
 while is_instance_valid(bedroom) and Time.get_ticks_msec()<limit:await physics_frame
 move_input(Vector2.ZERO);await process_frame
 if current_scene==null or current_scene.name!=&"TrainingGroundV02":fail("bedroom exit");return
 print("BEDROOM REAL MOVEMENT AND EXIT PASS")
 var training=current_scene;var player=training.player
 assert(training.dialogue_stage=="arrival" and not player.input_enabled)
 training._on_practice_hit(false);assert(training.light_hits==0)
 for i in range(3):training.next_button.pressed.emit()
 assert(player.input_enabled and not training.practice_ready)
 if not await walk_to(player,Vector2(0,-30)):fail("initial companion approach");return
 await press_action("interact");await process_frame
 assert(training.dialogue_stage=="practice" and not player.input_enabled)
 for i in range(4):training.next_button.pressed.emit()
 assert(training.practice_ready and player.input_enabled)
 print("ARRIVAL AND PRE-PRACTICE DIALOGUES PASS")
 if not await walk_to(player,Vector2(0,20)):fail("training route center "+str(player.position));return
 if not await walk_to(player,Vector2(175,48)):fail("training route around banner "+str(player.position));return
 if not await walk_to(player,Vector2(272,42),8):fail("training route dummy "+str(player.position));return
 player.facing_direction=(training.dummy.global_position-player.global_position).normalized()
 var combat_control=player.get_node("WorldCombatComponent")
 for i in range(2):
  await press_action("world_attack");await create_timer(1.3).timeout
  if training.light_hits!=i+1:fail("basic attack "+str(i)+" count="+str(training.light_hits)+" state="+str(player.visual.animator.state));return
 await press_action("world_skill");await create_timer(1.1).timeout
 if not training.dummy_complete:fail("skill did not unlock companion");return
 print("REAL ATTACKS AND SKILL PASS")
 if not await walk_to(player,Vector2(175,48)):fail("return past banner "+str(player.position));return
 if not await walk_to(player,Vector2(0,-30)):fail("companion approach "+str(player.position));return
 await press_action("interact");await process_frame
 assert(training.get_node("TutorialHUD/SparDialogue").visible)
 assert(training.dialogue_stage=="challenge")
 for i in range(3):training.next_button.pressed.emit()
 await create_timer(2).timeout
 var combat=training.get_node("TutorialHUD/SparringRoot").get_child(0);var ai=load("res://scripts/combat/combat_ai.gd");var deadline=Time.get_ticks_msec()+45000;var actions=0
 while not combat._resolved and Time.get_ticks_msec()<deadline:
  if not combat._animating and not combat.engine.finished:
   var actor=combat.engine.current_actor()
   if actor!=null and actor.team==0:
    var decision=ai.choose(combat.engine,combat.engine.current_actor_index);await combat._session_component.execute_action(str(decision.skill_id),decision.targets);actions+=1
  await process_frame
 assert(combat._resolved and combat.engine.winner_team==0)
 var fairy=combat._actor_for_uid(combat.engine.combatants[1].uid);assert(fairy.fairy_art.animation==&"surrender" and fairy.fairy_art.frame==7)
 print("ACTUAL DUEL PASS ",actions)
 combat._claim(true);await process_frame;assert(training.farewell_pending)
 var npc=training.get_node("CompanionNPC");var start=npc.position
 assert(training.dialogue_stage=="farewell")
 for i in range(5):training.next_button.pressed.emit()
 await create_timer(.45).timeout;assert(npc.sprite.animation==&"walk_left" and npc.position.distance_to(start)>10)
 await create_timer(1.65).timeout;assert(npc.get_node("TinyForm").modulate.a>.95)
 print("WALK AND TRANSFORM PASS")
 await create_timer(2.5).timeout
 assert(training.dialogue_stage=="travel" and player.has_node("FairyCompanion"))
 assert(not npc.get_node("TinyForm").visible and not gs.quest_domain.flags.get("tutorial_complete",false))
 print("FAIRY JOINS KAEL BEFORE TRANSPORT PASS")
 for i in range(2):training.next_button.pressed.emit()
 await scene_changed;await process_frame
 var village=current_scene;assert(village.name==&"StandaloneVillage" and village.checkpoint_player.has_node("FairyCompanion"))
 assert(gs.quest_domain.flags.get("tutorial_complete",false));assert(village.checkpoint_player.position.distance_to(Vector2(-2090,112))<5)
 print("FULL TUTORIAL PLAYTHROUGH PASS")
 await campaign(gs)

func campaign_frames(n:int):
 for i in range(n):await physics_frame

func campaign_travel(expected:String):
 var zone=current_scene
 var p=zone.checkpoint_player
 var trigger=zone.get_node("TransferPoints/ToNextZone/ToNextZoneTrigger")
 assert(trigger._story_unlocked() and p.input_enabled)
 p.global_position=trigger.global_position
 var deadline=Time.get_ticks_msec()+12000
 while current_scene==zone and Time.get_ticks_msec()<deadline:await physics_frame
 assert(current_scene!=null and current_scene.name==expected,"Travel failed to "+expected)
 await campaign_frames(8)
 assert(current_scene.checkpoint_player.has_node("FairyCompanion"))
 print("CAMPAIGN ARRIVAL ",expected)

func campaign_fight(router,group:String):
 var deadline=Time.get_ticks_msec()+90000
 while router.active_combat==null and Time.get_ticks_msec()<deadline:await process_frame
 var b=router.active_combat
 assert(b!=null and b.group_id==group)
 while b.engine==null and Time.get_ticks_msec()<deadline:await process_frame
 assert(b.engine!=null)
 b.engine.rng.seed=1
 var ai=load("res://scripts/combat/combat_ai.gd")
 var actions=0
 while not b._resolved and Time.get_ticks_msec()<deadline:
  if not b._animating and not b.engine.finished:
   var actor=b.engine.current_actor()
   if actor!=null and actor.team==0:
    var d=ai.choose(b.engine,b.engine.current_actor_index)
    await b._session_component.execute_action(str(d.skill_id),d.targets)
    actions+=1
  await process_frame
 assert(b._resolved and b.engine.winner_team==0,"Battle failed "+group)
 print("CAMPAIGN REAL VICTORY ",group," actions=",actions)
 b._claim(true)
 await campaign_frames(5)

func campaign_dialogue(dialog):
 var n=0
 while dialog.visible and n<40:
  dialog._finish_typing()
  if not dialog._node.get("choices",[]).is_empty():
   dialog._choose(dialog._node.choices[0])
  else:
   dialog._on_continue()
  n+=1
  await process_frame
 assert(not dialog.visible,"Dialogue did not close")

func campaign(gs):
 var zone=current_scene
 var p=zone.checkpoint_player
 var gerald=zone.get_node("VillageMap/GeraldBossSpawn/GeraldChallenge")
 var dialog=zone.get_node("UI/Dialogue")
 assert(not zone.get_node("TransferPoints/ToNextZone/ToNextZoneTrigger")._story_unlocked())
 p.global_position=gerald.global_position+Vector2(0,60)
 await campaign_frames(2)
 gerald.interact()
 await campaign_dialogue(dialog)
 await campaign_fight(zone.get_node("CombatRouter"),"gerald_boss_encounter")
 for id in ["gerald_kael_after_battle","gerald_kael_after_the_fall","gerald_kael_farewell"]:
  var deadline=Time.get_ticks_msec()+10000
  while (not dialog.visible or dialog._dialogue_id!=id) and Time.get_ticks_msec()<deadline:await process_frame
  assert(dialog.visible and dialog._dialogue_id==id)
  await campaign_dialogue(dialog)
  if id!="gerald_kael_farewell":
   var story
   deadline=Time.get_ticks_msec()+10000
   while story==null and Time.get_ticks_msec()<deadline:
    await process_frame
    story=zone.find_child("GeraldPostVictoryStory",true,false)
   assert(story!=null)
   story.get_node("SkipButton").pressed.emit()
   await story.tree_exited
 await campaign_frames(8)
 assert(gs.flags.get("village_gerald_backstory_seen",false))
 await campaign_travel("StandaloneZone01")
 zone=current_scene
 p=zone.checkpoint_player
 var npc=zone.get_node("Zone/RoyalGardenV3Decorations/Elathra")
 dialog=zone.get_node("NPCDialogueLayer/Dialogue")
 p.global_position=npc.global_position+Vector2(0,65)
 npc.interact()
 await process_frame
 assert(dialog.visible)
 for i in range(3):
  dialog._choose(dialog._node.choices[0])
 await campaign_frames(5)
 assert(gs.quest_domain.quest_state("elathra_first_audience")=="complete")
 await campaign_travel("StandaloneZone02")
 zone=current_scene
 p=zone.checkpoint_player
 for mob in zone.get_node("RoyalGatePatrol").get_children():
  if mob.has_method("receive_world_hit"):
   mob.receive_world_hit(120.0)
 assert(gs.quest_domain.quest_state("royal_gate_patrol")=="complete")
 await campaign_travel("StandaloneZone03")
 zone=current_scene
 p=zone.checkpoint_player
 for marker in ["RiverCrossing","EasternRuins"]:
  p.global_position=zone.get_node("WillowObjectives/"+marker).global_position
  await campaign_frames(5)
 assert(gs.quest_domain.quest_state("willow_crossing")=="complete")
 await campaign_travel("StandaloneZone04")
 zone=current_scene
 p=zone.checkpoint_player
 for name in ["BrokenMemorial","WeatheredPillar"]:
  var relic=zone.get_node("ElderwoodRelics/"+name)
  p.global_position=relic.global_position+Vector2(0,60)
  relic.interact()
 assert(gs.quest_domain.quest_state("elderwood_relics")=="complete")
 await campaign_travel("StandaloneZone05")
 zone=current_scene
 p=zone.checkpoint_player
 var cassien=zone.get_node("CassienRitual")
 dialog=zone.get_node("UI/Dialogue")
 p.global_position=cassien.global_position+Vector2(0,90)
 cassien.interact()
 var deadline=Time.get_ticks_msec()+12000
 while not dialog.visible and Time.get_ticks_msec()<deadline:await process_frame
 assert(dialog.visible)
 dialog._show_node("oath")
 dialog._choose(dialog._node.choices[0])
 await campaign_fight(zone.get_node("CombatRouter"),"cassien_encounter")
 assert(gs.flags.get("cassien_defeated",false))
 for b in zone.get_node("RuinsBraziers").get_children():
  p.global_position=b.global_position+Vector2(0,65)
  b.interact()
 assert(gs.quest_domain.quest_state("forsaken_braziers")=="complete")
 p.global_position=cassien.global_position+Vector2(0,90)
 cassien.interact()
 assert(dialog._dialogue_id=="cassien_ritual")
 dialog._show_node("awakening")
 dialog._show_node("fracture")
 dialog._show_node("departure")
 dialog._choose(dialog._node.choices[0])
 await cassien.departure_finished
 assert(gs.flags.get("ravienna_resurrected",false))
 await campaign_travel("StandaloneZone06")
 zone=current_scene
 p=zone.checkpoint_player
 var ravienna=zone.get_node("ReviennaEncounter")
 dialog=zone.get_node("UI/Dialogue")
 p.global_position=ravienna.global_position+Vector2(0,120)
 ravienna.interact()
 assert(dialog.visible)
 dialog._show_node("warning")
 dialog._choose(dialog._node.choices[0])
 await campaign_fight(zone.get_node("CombatRouter"),"revienna_encounter")
 assert(dialog.visible and dialog._dialogue_id=="revienna_victory")
 dialog._show_node("end")
 dialog._choose(dialog._node.choices[0])
 assert(gs.flags.get("ravienna_ending_seen",false) and not ravienna.can_interact() and p.input_enabled)
 for id in ["elathra_first_audience","royal_gate_patrol","willow_crossing","elderwood_relics","cassien_resurrection","forsaken_braziers"]:
  assert(gs.quest_domain.quest_state(id)=="complete")
 print("CONTINUOUS CAMPAIGN PASS gold=",gs.profile.gold," crystals=",gs.profile.crystals," visited=",gs.flags.get("discovered_fast_travel_zones"))
 zone.queue_free()
 for i in range(4):await process_frame
 root.get_node("AudioDirector").stop_all_audio_immediately()
 await create_timer(.5).timeout
 quit(0)
