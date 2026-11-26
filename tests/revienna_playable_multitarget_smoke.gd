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
 var party=[factory.build_from_character(CharacterInstance.create("ravienna","audit_ravienna"))]
 var enemies=factory.enemy_units("glade_mossling_pack")
 assert(enemies.size()==3)
 field.setup(party,enemies)
 for i in range(5):await process_frame
 var r=field.actor_for_uid(party[0].uid)
 var targets=[]
 for e in enemies:targets.append(field.actor_for_uid(e.uid))
 var sprite=r.ravienna_art.get_node("AnimatedSprite2D")
 assert(sprite.flip_h)
 field.play_attack(r,targets[0],"dark","lunar_wisp")
 await create_timer(0.70).timeout
 var seen=[]
 for fx in r._attack_effects:
  if is_instance_valid(fx) and fx.has_meta("revienna_target_uid"):
   seen.append(fx.get_meta("revienna_target_uid"))
   assert(fx.flip_h)
 assert(seen.size()==3)
 for e in enemies:assert(seen.has(e.uid))
 print("LUNAR WISP THREE DISTINCT PROJECTILE TARGETS PASS")
 await create_timer(0.5).timeout
 assert(r._attack_effects.is_empty() and sprite.animation==&"idle")
 targets[2].play_death()
 field.play_attack(r,targets[0],"dark","lunar_wisp")
 await create_timer(0.70).timeout
 assert(r._attack_effects.size()==2)
 r.cancel_attack_motion()
 await process_frame
 assert(r._attack_effects.is_empty())
 print("DEFEATED TARGET EXCLUDED AND INTERRUPTED PROJECTILES CLEANED")
 await create_timer(0.4).timeout
 field.play_attack(r,targets[0],"dark","hollow_moon_eclipse",true)
 await create_timer(1.3).timeout
 var eclipse=field.get_node("ReviennaEclipseEffects")
 assert(eclipse.get_node("Cracks/Effect0").visible)
 assert(eclipse.get_node("Cracks/Effect0").position.x>=targets[0].home_position.x-1)
 assert(eclipse.get_node("Corona/Effect0").position.x==r.home_position.x)
 await create_timer(1.1).timeout
 assert(not is_instance_valid(eclipse) and sprite.animation==&"idle")
 print("PLAYABLE ECLIPSE TARGETING AND RECOVERY PASS")
 field.queue_free()
 for i in range(12):await process_frame
 quit()
