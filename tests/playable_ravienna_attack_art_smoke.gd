extends SceneTree
func _initialize():call_deferred("_run")
func _run():
 if OS.get_environment("REVERIE_E2E_DISABLE_LOCAL_SAVE")!="1":
  quit(2)
  return
 var factory=load("res://scripts/combat/combat_factory.gd")
 var field=load("res://scenes/ui/battlefield.tscn").instantiate()
 root.add_child(field)
 field.size=Vector2(1200,400)
 var ids=[]
 for id in root.get_node("ContentDB").character_ids():
  if str(id).begins_with("ravienna"):ids.append(id)
 assert(not ids.is_empty())
 var checks=0
 for id in ids:
  var player=factory.build_from_character(CharacterInstance.create(id,"art_audit_"+id))
  var enemies=factory.enemy_units("cassien_encounter")
  assert(player!=null and not enemies.is_empty())
  field.setup([player],enemies)
  await process_frame
  var actor=field.actor_for_uid(player.uid)
  var enemy=field.actor_for_uid(enemies[0].uid)
  var sprite=actor.ravienna_art.get_node("AnimatedSprite2D")
  assert(sprite.sprite_frames.resource_path=="res://assets/characters/ravienna/playable_combat/combat_frames.tres" and sprite.flip_h)
  for skill in [["lunar_wisp","corruption_bolt"],["velvet_hex","shadow_lash"]]:
   actor.cancel_attack_motion()
   field.play_attack(actor,enemy,"dark",skill[0],false)
   assert(sprite.animation==skill[1] and sprite.sprite_frames.get_frame_count(skill[1])==6)
   var total=0.0
   for i in range(6):
    var tex=sprite.sprite_frames.get_frame_texture(skill[1],i)
    assert(tex.get_width()==128 and tex.get_height()==128 and tex.atlas.resource_path.contains("/playable_combat/"))
    total+=sprite.sprite_frames.get_frame_duration(skill[1],i)
   assert(total==8.0 and sprite.sprite_frames.get_animation_speed(skill[1])==8.0)
   await create_timer(1.15).timeout
   assert(sprite.animation==&"idle")
   checks+=1
  assert(sprite.sprite_frames.get_frame_count("ravienna_eclipse")==16)
  print("PLAYABLE PASS ",id)
  field.clear_actors()
  await process_frame
 var boss=load("res://assets/characters/revienna/combat/combat_frames.tres") as SpriteFrames
 assert(boss.get_frame_count("corruption_bolt")==8 and boss.get_frame_count("shadow_lash")==8 and boss.get_frame_count("ravienna_eclipse")==16)
 print("PLAYABLE_RAVIENNA_ART_PASS: ",checks," skill routes, original boss and ultimate clips preserved")
 field.queue_free()
 await process_frame
 quit(0)
