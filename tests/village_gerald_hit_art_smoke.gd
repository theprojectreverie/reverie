extends SceneTree
var failures: Array[String] = []
func _initialize():
 call_deferred("_run")
func check(ok: bool, label: String):
 print("CHECK ",label," = ",ok)
 if not ok: failures.append(label)
func _run():
 if OS.get_environment("REVERIE_E2E_DISABLE_LOCAL_SAVE") != "1":
  quit(2)
  return
 var factory = load("res://scripts/combat/combat_factory.gd")
 var boss = factory.enemy_units("gerald_boss_encounter")[0]
 var actor = load("res://scenes/ui/battlefield_actor.tscn").instantiate()
 root.add_child(actor)
 actor.setup(boss,false)
 var art = actor.get_node("GeraldFallenArt") as AnimatedSprite2D
 check(art.sprite_frames.get_frame_count(&"hit")==8,"eight frames")
 var duration := 0.0
 for i in range(8):
  duration += art.sprite_frames.get_frame_duration(&"hit",i)/art.sprite_frames.get_animation_speed(&"hit")
 check(is_equal_approx(duration,0.62),"hit duration")
 actor.take_hit()
 check(art.animation==&"hit" and art.is_playing(),"hit plays")
 await create_timer(0.72).timeout
 check(art.animation==&"idle" and art.is_playing(),"recovers to idle")
 actor.play_gerald_action(false)
 actor.take_hit()
 check(art.animation==&"attack","attack protected from asynchronous hit")
 actor.play_gerald_action(true)
 actor.take_hit()
 check(art.animation==&"earthquake","ultimate protected")
 actor.play_death()
 actor.take_hit()
 check(art.animation==&"defeat" and actor.dead,"surrender overrides all")
 await create_timer(2.35).timeout
 actor.take_hit()
 check(art.animation==&"defeat" and art.frame==13 and not art.is_playing() and art.visible and actor.modulate.a==1.0,"final kneeling pose intact")
 actor.queue_free()
 await process_frame
 print("RESULT ",failures)
 quit(0 if failures.is_empty() else 1)