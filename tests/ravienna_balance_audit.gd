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
 for level in [2,10,20,30,40,50]:
  for instance in gs.roster_domain.party_instances():
   instance.level=level
  var wins=0
  var turns=0
  for seed in range(30):
   var engine=engine_script.new()
   engine.setup(factory.player_units(),factory.enemy_units("revienna_encounter"),seed+1)
   engine.start()
   for i in range(100):
    if engine.finished:break
    var idx=engine.current_actor_index
    if idx<0:break
    var choice=ai.choose(engine,idx)
    if str(choice.get("skill_id","")).is_empty():engine.advance_turn()
    else:engine.execute(idx,choice.skill_id,choice.targets)
    turns+=1
   if engine.winner_team==0:wins+=1
  print("RAVIENNA LEVEL ",level," wins ",wins,"/30; average actions ",float(turns)/30.0)
 quit()
