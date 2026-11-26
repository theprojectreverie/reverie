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
 var battle=scene.instantiate()
 battle.group_id="fallen_aqueduct_sentinels"
 current_scene.add_child(battle)
 for i in range(12):await process_frame
 battle.engine.rng.seed=7
 var unit
 for u in battle.engine.combatants:
  if u.def_id=="ravienna":unit=u
  if u.team==0:
   # Fixture-only survivability, without altering attack or energy.
   u.max_hp=2000.0
   u.hp=u.max_hp
 assert(unit!=null)
 var actor=battle._actor_for_uid(unit.uid)
 var sprite=actor.ravienna_art.get_node("AnimatedSprite2D")
 var observed={"ultimate":false,"healed":false}
 sprite.frame_changed.connect(func():
  if sprite.animation==&"ravienna_eclipse" and sprite.frame==10:
   assert(battle._animating)
   assert(battle._battlefield.get_node_or_null("ReviennaEclipseEffects")!=null)
   observed.ultimate=true
 )
 var casts=0
 var ticks=0
 while ticks<4000 and not battle._resolved and not observed.ultimate:
  ticks+=1
  if not battle._animating and not battle.engine.finished:
   var current=battle.engine.current_actor()
   if current!=null and current.team==0:
    if current!=unit:
     await battle._session_component.defend()
    else:
     var living=battle.engine.living(1)
     var ready=unit.ultimate_ready()
     var chosen="hollow_moon_eclipse" if ready else ("lunar_wisp" if casts%2==0 else "velvet_hex")
     var before=unit.energy
     var hp_before=unit.hp
     await battle._session_component.execute_action(chosen,[living[0].combat_index])
     print("NATURAL ENERGY ",chosen," ",before," -> ",unit.energy," hp ",hp_before," -> ",unit.hp)
     if chosen=="velvet_hex" and unit.hp>hp_before:observed.healed=true
     if ready:
      assert(unit.energy<before and observed.ultimate)
     else:
      assert(unit.energy>before or unit.ultimate_ready())
      casts+=1
  await process_frame
 assert(casts>=2 and observed.ultimate and observed.healed)
 assert(sprite.animation==&"idle" and actor._attack_effects.is_empty())
 print("NATURAL ENERGY, LIFESTEAL, ULTIMATE AND RECOVERY PASS ",casts," ordinary spells")
 battle._claim(false)
 for i in range(12):await process_frame
 current_scene.queue_free()
 for i in range(12):await process_frame
 root.get_node("AudioDirector").stop_all_audio_immediately()
 await create_timer(1.0).timeout
 quit()
