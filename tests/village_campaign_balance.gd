extends SceneTree
func _initialize(): call_deferred("_run")
func _run():
 var factory=load("res://scripts/combat/combat_factory.gd")
 var ai=load("res://scripts/combat/combat_ai.gd")
 var engine_script=load("res://scripts/combat/combat_engine.gd")
 var groups=["village_slime_1","village_slime_2","village_crimson_encounter","village_crownling_1","village_crownling_2","village_crownling_3","village_nyx_encounter","gerald_boss_encounter"]
 var wins:={}
 var turns:={}
 var quakes=0
 var clears=0
 for seed in range(100):
  var chars=[CharacterInstance.create("kael","test_kael")]
  var success=true
  for group in groups:
   var duel=group in ["village_crimson_encounter","village_nyx_encounter"]
   var party=[]
   for c in chars:
    if not duel or c.char_id=="kael":party.append(factory.build_from_character(c))
   var foes=factory.enemy_units(group,"village_recruited" if group=="gerald_boss_encounter" else "")
   var engine=engine_script.new()
   engine.setup(party,foes,seed+1)
   engine.start()
   var n=0
   for i in range(160):
    if engine.finished:break
    var idx=engine.current_actor_index
    if idx<0:break
    var choice=ai.choose(engine,idx)
    if str(choice.get("skill_id","")).is_empty():engine.advance_turn()
    else:
     for event in engine.execute(idx,choice.skill_id,choice.targets):
      if event.get("type","")=="action" and event.get("skill_id","")=="gerald_village_earthquake":quakes+=1
    n+=1
   if engine.winner_team!=0:
    success=false
    break
   wins[group]=int(wins.get(group,0))+1
   turns[group]=int(turns.get(group,0))+n
   var xp=int(root.get_node("ContentDB").get_enemy_group(group).get("rewards",{}).get("xp",0))
   for c in chars:
    if not duel or c.char_id=="kael":
     c.xp+=xp
     while c.xp>=100+(c.level-1)*85:
      c.xp-=100+(c.level-1)*85
      c.level+=1
   if group=="village_crimson_encounter": chars.append(CharacterInstance.create("crimson_witch_legendary","test_crimson"))
   if group=="village_nyx_encounter": chars.append(CharacterInstance.create("nyx","test_nyx"))
   var bonus={"village_slime_2":60,"village_crimson_encounter":60,"village_crownling_3":100,"village_nyx_encounter":80}.get(group,0)
   for c in chars:
    c.xp+=bonus
    while c.xp>=100+(c.level-1)*85:
     c.xp-=100+(c.level-1)*85
     c.level+=1
  if success:clears+=1
 print("BALANCE wins=",wins," turns=",turns," clears=",clears," quakes=",quakes)
 quit()
