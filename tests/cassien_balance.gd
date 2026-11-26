extends SceneTree
func _initialize():
 call_deferred("_run")
func _run():
 if OS.get_environment("REVERIE_E2E_DISABLE_LOCAL_SAVE")!="1":
  quit(2)
  return
 root.get_node("GameState").new_game("Cassien QA")
 var factory=load("res://scripts/combat/combat_factory.gd")
 var engine_script=load("res://scripts/combat/combat_engine.gd")
 var ai=load("res://scripts/combat/combat_ai.gd")
 var wins=0
 var actions=0
 for seed in range(100):
  var party=factory.player_units()
  var enemies=factory.enemy_units("cassien_encounter")
  var engine=engine_script.new()
  engine.setup(party,enemies,seed+1)
  engine.start()
  for i in range(100):
   if engine.finished:break
   var idx=engine.current_actor_index
   if idx<0:break
   var choice=ai.choose(engine,idx)
   if str(choice.get("skill_id","")).is_empty():engine.advance_turn()
   else:engine.execute(idx,choice.skill_id,choice.targets)
   actions+=1
  if engine.winner_team==0:wins+=1
 print("CASSIEN BALANCE ",wins,"/100 wins, mean actions ",float(actions)/100.0)
 quit(0 if wins>=70 else 1)
