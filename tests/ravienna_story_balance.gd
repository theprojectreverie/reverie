extends SceneTree
func _initialize():
 call_deferred("_run")
func _run():
 if OS.get_environment("REVERIE_E2E_DISABLE_LOCAL_SAVE")!="1":
  quit(2)
  return
 var gs=root.get_node("GameState")
 var factory=load("res://scripts/combat/combat_factory.gd")
 var engine_script=load("res://scripts/combat/combat_engine.gd")
 var ai=load("res://scripts/combat/combat_ai.gd")
 gs.quest_domain.flags["six_zone_checkpoint"]={"zone":"StandaloneVillage"}
 gs.reward_domain.apply_battle_result("gerald_boss_encounter",true)
 gs.quest_domain.flags["six_zone_checkpoint"]={"zone":"StandaloneZone01"}
 for id in ["elathra_first_audience","royal_gate_patrol","willow_crossing","elderwood_relics","forsaken_braziers"]:
  gs.roster_domain.add_party_xp(int(root.get_node("ContentDB").get_quest(id).rewards.xp))
 for id in ["royal_gate_patrol_1","royal_gate_patrol_2","cassien_encounter"]:
  gs.reward_domain.apply_battle_result(id,true)
 for p in gs.roster_domain.party_instances(): print("ARRIVAL ",p.char_id," level ",p.level," xp ",p.xp)

 var original=factory.enemy_units("revienna_encounter")[0]
 var story=factory.enemy_units("revienna_encounter","story_tower")[0]
 print("ORIGINAL ",original.max_hp," STORY ",story.max_hp," PHASES ",story.phases.size())
 assert(is_equal_approx(original.max_hp,4230.0) and is_equal_approx(story.max_hp,1000.0) and story.phases.size()==2)
 var wins=0
 var turns=0
 var losses=0
 var phase_fights=0
 var ultimate_fights=0
 for seed in range(100):
  var engine=engine_script.new()
  engine.setup(factory.player_units(),factory.enemy_units("revienna_encounter","story_tower"),seed+1)
  engine.start()
  var cast_eclipse=false
  for i in range(150):
   if engine.finished:break
   var idx=engine.current_actor_index
   if idx<0:break
   var choice=ai.choose(engine,idx)
   if str(choice.get("skill_id","")).is_empty():engine.advance_turn()
   else:
    for event in engine.execute(idx,choice.skill_id,choice.targets):
     if event.get("type")=="action" and event.get("skill_id")=="ravienna_eclipse":
      cast_eclipse=true
   turns+=1
  if engine.winner_team==0:wins+=1
  else:losses+=1
  if cast_eclipse:ultimate_fights+=1
  for line in engine.log:
   if "remaining power" in str(line):
    phase_fights+=1
    break
 print("STORY PROFILE wins ",wins,"/100 losses ",losses," average actions ",float(turns)/100," final-phase fights ",phase_fights," ultimate fights ",ultimate_fights)
 root.get_node("AudioDirector").stop_all_audio_immediately()
 await create_timer(0.35).timeout
 quit(0 if wins>=85 else 1)