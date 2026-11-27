extends SceneTree
func _initialize(): call_deferred("_run")
func _run():
 if OS.get_environment("REVERIE_E2E_DISABLE_LOCAL_SAVE")!="1":
  quit(2)
  return
 var factory=load("res://scripts/combat/combat_factory.gd")
 var field=load("res://scenes/ui/battlefield.tscn").instantiate()
 root.add_child(field)
 field.size=Vector2(1200,400)
 var party=[]
 for id in ["mirene_legendary","mirene_mythic"]:
  party.append(factory.build_from_character(CharacterInstance.create(id,"audit_"+id)))
 var enemies=factory.enemy_units("cassien_encounter")
 field.setup(party,enemies)
 for i in range(3): await process_frame
 var enemy=field.actor_for_uid(enemies[0].uid)
 for u in party:
  var a=field.actor_for_uid(u.uid)
  assert(u.display_name.begins_with("Mir\u00e9ne"))
  assert(is_instance_valid(a.live_art) and a.live_art.visible and not a.visual.visible)
  assert(a.live_art.animation==&"idle" and a.live_art.flip_h)
  for clip in [["","basic_attack"],["shadow_feint","skill_1"],["corruption_bolt","skill_2"],["hollow_wail","ultimate"]]:
   field.play_attack(a,enemy,"dark",clip[0],clip[0]=="hollow_wail")
   assert(a.live_art.animation==StringName(clip[1]))
   assert(a.live_art.sprite_frames.get_frame_count(StringName(clip[1]))>1)
  await create_timer(1.8).timeout
  assert(a.live_art.animation==&"idle")
  a.take_hit()
  assert(a.live_art.animation==&"hit")
  a.play_death()
  assert(a.live_art.animation==&"defeat")
  print("HARLEQUIN AUTHORED COMBAT PASS ",u.def_id)
 field.queue_free()
 await process_frame
 quit()
