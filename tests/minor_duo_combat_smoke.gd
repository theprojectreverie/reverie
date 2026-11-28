extends SceneTree
func _initialize(): call_deferred("_run")
func _run():
 if OS.get_environment("REVERIE_E2E_DISABLE_LOCAL_SAVE") != "1":
  quit(2)
  return
 var factory=load("res://scripts/combat/combat_factory.gd")
 for allied in [false,true]:
  var field=load("res://scenes/ui/battlefield.tscn").instantiate()
  root.add_child(field)
  field.size=Vector2(1200,400)
  var party=[factory.build_from_character(CharacterInstance.create("kael","minor_kael"))]
  if allied:
   for id in ["crimson_witch_legendary","nyx"]:
    party.append(factory.build_from_character(CharacterInstance.create(id,"minor_"+id)))
  var enemies=factory.enemy_units("cassien_encounter") if allied else factory.enemy_units("village_crimson_encounter") + factory.enemy_units("village_nyx_encounter")
  field.setup(party,enemies)
  for i in range(3): await process_frame
  var units=party.slice(1) if allied else enemies
  assert(units.size()==2)
  var target=field.actor_for_uid(enemies[0].uid if allied else party[0].uid)
  var kael=field.actor_for_uid(party[0].uid)
  assert(is_instance_valid(kael))
  for u in units:
   var a=field.actor_for_uid(u.uid)
   assert(is_instance_valid(a.live_art) and a.live_art.visible and not a.visual.visible)
   assert(a.live_art.animation==&"idle" and a.is_player==allied)
   assert(a.live_art.flip_h==allied)
   assert(a.position.distance_to(kael.position)>1.0)
   for skill in ["",u.skills[0],u.skills[1]]:
    field.play_attack(a,target,"dark",skill,false)
    var expected=a.minor_action_clip(skill,false)
    if a.is_crimson_witch():
     assert(a.live_art.animation==&"approach")
     await create_timer(0.34).timeout
     assert(a.live_art.animation==expected)
     await create_timer(0.61).timeout
     assert(a.live_art.animation in [&"retreat",&"idle"])
     await create_timer(0.40).timeout
    else:
     assert(a.live_art.animation==expected)
     await create_timer(1.0).timeout
    assert(a.live_art.animation==&"idle")
    assert(a.position.distance_to(a.home_position)<1.0)
   a.take_hit()
   assert(a.live_art.modulate.r>1.0)
   a.play_death()
   assert(a.dead)
   await create_timer(0.5).timeout
   assert(a.live_art.modulate.a<0.4)
   print("DUO PASS ",u.def_id," allied=",allied)
  field.queue_free()
  await process_frame
 print("MINOR DUO COMPLETE")
 quit()
