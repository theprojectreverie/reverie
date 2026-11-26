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
 var cases=[["cassien_legendary","ravienna"],["cassien_mythic","ravienna_mythic"]]
 var checks=0
 for pair in cases:
  var party=[]
  for id in pair:
   party.append(factory.build_from_character(CharacterInstance.create(id,"audit_"+id)))
  assert(party[0]!=null and party[1]!=null, "Active playable definitions missing")
  var enemies=factory.enemy_units("cassien_encounter") if pair==cases[0] else factory.enemy_units("revienna_encounter")
  field.setup(party,enemies)
  for j in range(3):await process_frame
  var c=field.actor_for_uid(party[0].uid)
  var r=field.actor_for_uid(party[1].uid)
  var e=field.actor_for_uid(enemies[0].uid)
  assert(c.cassien_art.visible and r.ravienna_art.visible and not c.visual.visible and not r.visual.visible)
  assert(c.home_position.x<e.home_position.x and r.home_position.x<e.home_position.x and c.home_position!=r.home_position)
  var sprite=r.ravienna_art.get_node("AnimatedSprite2D")
  assert(c.cassien_art.flip_h and sprite.flip_h)
  var boss_sprite: AnimatedSprite2D = e.cassien_art if is_instance_valid(e.cassien_art) else e.ravienna_art.get_node("AnimatedSprite2D")
  assert(not boss_sprite.flip_h)
  assert(c.cassien_art.sprite_frames.resource_path.ends_with("cassien/combat/combat_frames.tres"))
  assert((sprite.sprite_frames.get_frame_texture(&"idle",0) as AtlasTexture).atlas.resource_path.contains("/revienna/combat/Revienna_Combat_Idle_Left_128.png"))
  field.play_attack(c,e,"dark")
  assert(c.cassien_art.animation==&"attack" and c.cassien_art.flip_h)
  field.play_attack(r,e,"dark")
  assert(sprite.animation==&"corruption_bolt" and sprite.flip_h)
  r.cancel_attack_motion()
  for skill in [["umbral_rend","heavy_attack"],["blood_waltz","crimson_crescent"],["soul_drain","crimson_requiem"]]:
   field.play_attack(c,e,"dark",skill[0],skill[0]=="soul_drain")
   assert(c.cassien_art.animation==skill[1] and c.cassien_art.flip_h and not boss_sprite.flip_h)
   assert(c.cassien_action_duration(skill[0],skill[0]=="soul_drain")>=c.cassien_impact_time(skill[0],skill[0]=="soul_drain"))
   checks+=1
  for skill in [["lunar_wisp","corruption_bolt"],["velvet_hex","shadow_lash"],["hollow_moon_eclipse","ravienna_eclipse"]]:
   r.cancel_attack_motion()
   field.play_attack(r,e,"dark",skill[0],skill[0]=="hollow_moon_eclipse")
   assert(sprite.animation==skill[1] and sprite.flip_h and not boss_sprite.flip_h)
   checks+=1
  if pair==cases[0]:
   await create_timer(1.3).timeout
   var fx=field.get_node("ReviennaEclipseEffects")
   assert(fx.get_node("Cracks/Effect0").position.x>=e.home_position.x-1)
   assert(r.position.is_equal_approx(r.home_position))
   if DisplayServer.get_name()!="headless":
    await RenderingServer.frame_post_draw
    print("CAPTURE ",root.get_texture().get_image().save_png("C:/Users/quoth/Downloads/reverie_summonable_combat_review.png"))
   await create_timer(1.1).timeout
   assert(not is_instance_valid(fx) and sprite.animation==&"idle")
  c.play_victory()
  r.play_victory()
  assert(c.cassien_art.animation==&"idle" and sprite.animation==&"idle")
  c.take_hit()
  r.take_hit()
  assert(c.cassien_art.animation==&"hit" and sprite.animation==&"hit")
  c.play_death()
  r.play_death()
  assert(c.dead and r.dead and c.cassien_art.animation==&"defeat" and sprite.animation==&"defeat")
  print("PAIR PASS ",pair)
  field.clear_actors()
  await process_frame
 print("SUMMONABLE ART PASS ",checks," skill routes; all 4 currently playable entries, formation, recovery, hit and defeat")
 field.queue_free()
 await process_frame
 quit()
