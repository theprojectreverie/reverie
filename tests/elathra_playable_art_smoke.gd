extends SceneTree
func _initialize(): call_deferred("_run")
func _run():
 if OS.get_environment("REVERIE_E2E_DISABLE_LOCAL_SAVE") != "1":
  quit(2)
  return
 var source = load("res://scripts/art/sprite_frames_actor_source.gd")
 for id in ["elathra","elathra_mythic"]:
  var src = source.register_playable(id)
  var errors = src.validate_sheets()
  if not errors.is_empty():
   printerr(id, " world validation: ", errors)
   quit(1)
   return
  assert(src.has_frames())
  print("WORLD PASS ",id)
 var factory=load("res://scripts/combat/combat_factory.gd")
 var field=load("res://scenes/ui/battlefield.tscn").instantiate()
 root.add_child(field)
 field.size=Vector2(1200,400)
 var party=[]
 for id in ["elathra","elathra_mythic"]:
  party.append(factory.build_from_character(CharacterInstance.create(id,"audit_"+id)))
 var enemies=factory.enemy_units("cassien_encounter")
 field.setup(party,enemies)
 for i in range(3): await process_frame
 var enemy=field.actor_for_uid(enemies[0].uid)
 for u in party:
  var a=field.actor_for_uid(u.uid)
  assert(is_instance_valid(a.elathra_art) and a.elathra_art.visible and not a.visual.visible)
  assert(a.elathra_art.animation==&"idle")
  field.play_attack(a,enemy,"dark","",false)
  assert(a.elathra_art.animation==&"walk")
  await create_timer(0.30).timeout
  assert(a.elathra_art.animation==&"attack")
  await create_timer(0.80).timeout
  assert(a.elathra_art.animation==&"idle")
  assert(a.position.distance_to(a.home_position)<1.0)
  for clip in ["lunar_wisp","crimson_binding","hollow_wail"]:
   field.play_attack(a,enemy,"dark",clip,clip=="hollow_wail")
   assert(a.elathra_art.animation==StringName(clip))
   assert(a.elathra_art.sprite_frames.get_frame_count(StringName(clip))>1)
  await create_timer(1.8).timeout
  assert(a.elathra_art.animation==&"idle")
  a.take_hit()
  assert(a.elathra_art.animation==&"hit")
  a.play_death()
  assert(a.elathra_art.animation==&"defeat")
  await create_timer(1.2).timeout
  assert(a.elathra_art.animation==&"defeat")
  print("COMBAT PASS ",u.def_id)
 field.queue_free()
 await process_frame
 quit()
