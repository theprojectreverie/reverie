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
 var cases=[["cassien","ravienna"],["cassien_common","ravienna_common"],["cassien_epic","ravienna_rare"],["cassien_legendary","ravienna_epic"],["cassien_mythic","ravienna_mythic"]]
 var checks=0
 for pair in cases:
  var party=[]
  for id in pair:
   party.append(factory.build_from_character(CharacterInstance.create(id,"audit_"+id)))
  var enemies=factory.enemy_units("cassien_encounter")
  field.setup(party,enemies)
  for j in range(3):await process_frame
  var c=field.actor_for_uid(party[0].uid)
  var r=field.actor_for_uid(party[1].uid)
  var e=field.actor_for_uid(enemies[0].uid)
  assert(c.cassien_art.visible and r.ravienna_art.visible and not c.visual.visible and not r.visual.visible)
  assert(c.home_position.x<e.home_position.x and r.home_position.x<e.home_position.x and c.home_position!=r.home_position)
  var sprite=r.ravienna_art.get_node("AnimatedSprite2D")
  assert(c.cassien_art.flip_h and sprite.flip_h and not e.cassien_art.flip_h)
  for skill in [["umbral_rend","heavy_attack"],["blood_waltz","crimson_crescent"],["soul_drain","crimson_requiem"]]:
   field.play_attack(c,e,"dark",skill[0],skill[0]=="soul_drain")
   assert(c.cassien_art.animation==skill[1])
   checks+=1
  for skill in [["lunar_wisp","corruption_bolt"],["velvet_hex","shadow_lash"],["hollow_moon_eclipse","ravienna_eclipse"]]:
   r.cancel_attack_motion()
   field.play_attack(r,e,"dark",skill[0],skill[0]=="hollow_moon_eclipse")
   assert(sprite.animation==skill[1])
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
 print("SUMMONABLE ART PASS ",checks," skill routes; all 10 entries, formation, recovery, hit and defeat")
 field.queue_free()
 await process_frame
 quit()
