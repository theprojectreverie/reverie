extends SceneTree
func _initialize(): call_deferred("_run")

func _run():
 if OS.get_environment("REVERIE_E2E_DISABLE_LOCAL_SAVE")!="1":
  quit(2)
  return
 var gs=root.get_node("GameState")
 gs.quest_domain.flags["tutorial_complete"]=true
 change_scene_to_file("res://scenes/world/six_zone_reverie/individual_zones/zone_05_forsaken_ruins_standalone.tscn")
 await scene_changed
 for i in range(10):await process_frame
 var added=gs.roster_domain.add_character("ravienna")
 var instance=added.instance
 instance.level=15
 var party=[instance.uid]
 for member in gs.roster_domain.roster:
  if member.char_id=="kael" or member.char_id=="lilith":
   member.level=15
   party.append(member.uid)
 assert(gs.roster_domain.set_party(party))
 var scene=load("res://scenes/ui/combat_screen.tscn")
 var skills=["lunar_wisp","velvet_hex","hollow_moon_eclipse"]
 var clips=["corruption_bolt","shadow_lash","ravienna_eclipse"]
 for steps in range(3):
  var test_battle=scene.instantiate()
  test_battle.group_id="fallen_aqueduct_sentinels"
  current_scene.add_child(test_battle)
  for i in range(12):await process_frame
  test_battle.engine.rng.seed=7
  var unit
  for u in test_battle.engine.combatants:
   if u.def_id=="ravienna":unit=u
  assert(unit!=null and unit.team==0 and not unit.is_boss)
  assert(unit.skills==["lunar_wisp","velvet_hex"] and unit.ultimate=="hollow_moon_eclipse")
  var actor=test_battle._actor_for_uid(unit.uid)
  var sprite=actor.ravienna_art.get_node("AnimatedSprite2D")
  var observed={"clip":false,"peak":false}
  sprite.animation_changed.connect(func():
   if str(sprite.animation)==clips[steps]:observed.clip=true
  )
  sprite.frame_changed.connect(func():
   if sprite.animation==&"ravienna_eclipse" and sprite.frame==10:
    var fx=test_battle._battlefield.get_node_or_null("ReviennaEclipseEffects")
    assert(fx!=null and fx.get_node("Eruptions/Effect0").visible)
    assert(test_battle._animating)
    observed.peak=true
  )
  var ticks=0
  while ticks<1500 and not test_battle._resolved:
   ticks+=1
   if not test_battle._animating and not test_battle.engine.finished:
    var current=test_battle.engine.current_actor()
    if current!=null and current.team==0:
     if current==unit:break
     await test_battle._session_component.defend()
   await process_frame
  assert(not test_battle._resolved and test_battle.engine.current_actor()==unit)
  var living=test_battle.engine.living(1)
  var before={}
  for e in living:before[e.uid]=e.hp
  if steps==2:
   assert(not unit.ultimate_ready())
   unit.energy=unit.max_energy
  var energy_before=unit.energy
  await test_battle._session_component.execute_action(skills[steps],[living[0].combat_index])
  var damaged=0
  for e in living:
   if e.hp<before[e.uid]:damaged+=1
  assert(damaged==(1 if steps==1 else living.size()))
  if steps==0:assert(unit.energy>=energy_before+18.0)
  if steps==2:
   assert(unit.energy<unit.max_energy)
   assert(observed.peak)
  assert(observed.clip and sprite.animation==&"idle" and actor._attack_effects.is_empty())
  print("LIVE SKILL ",skills[steps]," damaged=",damaged," energy=",unit.energy)
  var test_ref=weakref(test_battle)
  test_battle._claim(false)
  for i in range(12):await process_frame
  assert(test_ref.get_ref()==null)
  assert(not gs.quest_domain.flags.get("revienna_defeated",false))
 print("ACTUAL ENGINE SKILLS, ANIMATION RECOVERY AND RETREAT PASS")
 # A separate normal encounter must reach a genuine victory through engine actions.
 var battle=scene.instantiate()
 battle.group_id="glade_mossling_pack"
 current_scene.add_child(battle)
 for i in range(12):await process_frame
 var ai=load("res://scripts/combat/combat_ai.gd")
 var ticks=0
 var actions=0
 while not battle._resolved and ticks<3000:
  ticks+=1
  if not battle._animating and not battle.engine.finished:
   var current=battle.engine.current_actor()
   if current!=null and current.team==0:
    var decision=ai.choose(battle.engine,battle.engine.current_actor_index)
    await battle._session_component.execute_action(str(decision.skill_id),decision.targets)
    actions+=1
  await process_frame
 assert(battle._resolved and battle.engine.winner_team==0)
 print("REAL VICTORY ",actions," player actions")
 battle._claim(true)
 for i in range(12):await process_frame
 assert(not gs.quest_domain.flags.get("revienna_defeated",false))
 current_scene.queue_free()
 for i in range(12):await process_frame
 root.get_node("AudioDirector").stop_all_audio_immediately()
 await create_timer(0.5).timeout
 print("PLAYABLE REVIENNA LIVE COMBAT REGRESSION PASS")
 quit()
