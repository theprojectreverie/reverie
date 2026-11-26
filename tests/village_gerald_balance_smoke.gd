extends SceneTree
func _initialize():
 call_deferred("_run")
func _run():
 if OS.get_environment("REVERIE_E2E_DISABLE_LOCAL_SAVE")!="1":
  quit(2)
  return
 var gs=root.get_node("GameState")
 gs.quest_domain.flags["six_zone_checkpoint"]={"zone":"StandaloneVillage","x":-2090.0,"y":112.0}
 var factory=load("res://scripts/combat/combat_factory.gd")
 var engine_script=load("res://scripts/combat/combat_engine.gd")
 var ai=load("res://scripts/combat/combat_ai.gd")
 var standard=factory.enemy_units("gerald_boss_encounter")[0]
 var local=factory.enemy_units("gerald_boss_encounter","village_solo")[0]
 var intact=is_equal_approx(standard.max_hp,2460.0) and is_equal_approx(standard.atk,61.5) and is_equal_approx(local.max_hp,330.0) and is_equal_approx(local.atk,1.0) and local.phases.size()==2 and standard.ultimate=="gerald_earthquake" and local.ultimate=="gerald_village_earthquake" and local.energy==65.0
 print("STANDARD ",standard.max_hp," hp; VILLAGE ",local.max_hp," hp; profiles correct=",intact)
 var wins=0
 var losses=0
 var earthquake_fights=0
 var earthquake_casts=0
 var flame_casts=0
 var max_quakes=0
 for seed in range(100):
  var party=factory.player_units()
  var enemies=factory.enemy_units("gerald_boss_encounter","village_solo")
  var engine=engine_script.new()
  engine.setup(party,enemies,seed+1)
  engine.start()
  var cast_count=0
  for i in range(80):
   if engine.finished:break
   var idx=engine.current_actor_index
   if idx<0:break
   var choice=ai.choose(engine,idx)
   if str(choice.get("skill_id","")).is_empty():engine.advance_turn()
   else:
    var events=engine.execute(idx,choice.skill_id,choice.targets)
    for event in events:
     if str(event.get("type",""))=="action":
      if str(event.get("skill_id",""))=="gerald_village_earthquake":
       cast_count+=1
      elif str(event.get("skill_id",""))=="gerald_village_flame":
       flame_casts+=1
  if cast_count>0:earthquake_fights+=1
  earthquake_casts+=cast_count
  max_quakes=maxi(max_quakes,cast_count)
  if engine.winner_team==0:wins+=1
  elif engine.winner_team==1:losses+=1
 print("VILLAGE BALANCE wins=",wins," losses=",losses,"/100")
 print("EARTHQUAKE fights=",earthquake_fights," casts=",earthquake_casts," max per fight=",max_quakes," flame strikes=",flame_casts)
 quit(0 if intact and wins>=90 and earthquake_fights>=90 and flame_casts>=90 else 1)