extends SceneTree
func _initialize(): call_deferred("_run")
func _run():
 if OS.get_environment("REVERIE_E2E_DISABLE_LOCAL_SAVE") != "1":
  quit(2)
  return
 var gs=root.get_node("GameState")
 var q=gs.quest_domain
 var roster=gs.roster_domain
 for id in ["village_clear_approach","village_crimson_duel","village_clear_ruins","village_nyx_duel","village_gerald_trial"]:
  q.quests.erase(id)
 for flag in q.flags.keys():
  if str(flag).begins_with("village_encounter_won_") or str(flag).begins_with("village_recruited_") or flag in ["village_gerald_defeated","village_lilith_awakened","village_gerald_backstory_pending"]:
   q.flags.erase(flag)
 var v=load("res://scenes/world/village/imported_village/village_playable.tscn").instantiate()
 root.add_child(v)
 current_scene=v
 for i in range(5): await physics_frame
 var map=v.get_node("VillageMap")
 var gerald=map.get_node("GeraldBossSpawn/GeraldChallenge")
 var stages=["VillageSlime1","VillageSlime2","CrimsonEncounter","VillageCrownling1","VillageCrownling2","VillageCrownling3","NyxEncounter"]
 var space=v.get_world_2d().direct_space_state
 for name in stages:
  var point=map.get_node(name).global_position
  var query=PhysicsShapeQueryParameters2D.new()
  var shape=CircleShape2D.new()
  shape.radius=28
  query.shape=shape
  query.transform=Transform2D(0,point)
  query.collision_mask=1
  assert(space.intersect_shape(query,1).is_empty())
 print("ALL SEVEN CLEAR")
 var policy=load("res://scripts/world/six_zone_reverie/village_witch_duo_encounter.gd")
 assert(policy.permits_local_story(true,true,false,false))
 assert(not policy.permits_local_story(true,false,false,false))
 assert(not policy.permits_local_story(true,true,true,false))
 assert(not policy.permits_local_story(true,true,false,true))
 print("PUBLIC ALPHA VILLAGE POLICY PASS")
 assert(q.quest_state("village_clear_approach")=="active")
 assert(not gerald.can_interact())
 assert(roster.effective_party_ids().size()==1)
 for i in range(stages.size()):
  var n=map.get_node(stages[i])
  assert(n.visible and n.can_interact())
  if i<2: assert(not map.get_node("CrimsonEncounter").visible)
  if i<6: assert(not map.get_node("NyxEncounter").visible)
  assert(not gerald.can_interact())
  # Exercise reward pipeline and world result handler, not fake account ownership.
  n.engaged=true
  n._on_battle_finished({"group_id":n.group_id,"victory":false})
  assert(n.can_interact())
  n.engaged=true
  gs.reward_domain.apply_battle_result(n.group_id,true)
  n._on_battle_finished({"group_id":n.group_id,"victory":true})
  assert(not n.visible and n.defeated)
  if i==2:
   assert(roster.owns_character("crimson_witch_legendary"))
   assert(roster.effective_party_ids().size()==2)
  if i==6:
   assert(roster.owns_character("nyx"))
   assert(roster.effective_party_ids().size()==3)
  print("STAGE PASS ",n.group_id," active_party=",roster.effective_party_ids().size())
 assert(gerald.can_interact())
 assert(q.quest_state("village_gerald_trial")=="active")
 var factory=load("res://scripts/combat/combat_factory.gd")
 var party=factory.player_units()
 assert(party.size()==3)
 var boss=factory.enemy_units("gerald_boss_encounter","village_recruited")[0]
 var old=factory.enemy_units("gerald_boss_encounter","village_solo")[0]
 assert(boss.max_hp>old.max_hp and boss.atk>old.atk and boss.defense>old.defense)
 print("GERALD PROFILE PASS hp=",boss.max_hp," atk=",boss.atk," party=",party.size())
 v.queue_free()
 await process_frame
 print("VILLAGE PROGRESSION COMPLETE")
 quit()
