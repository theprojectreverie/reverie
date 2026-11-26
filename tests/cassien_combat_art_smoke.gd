extends SceneTree
var failures: Array[String]=[]
func _initialize():
 call_deferred("run")
func check(ok: bool, label: String):
 print("CHECK ",label," = ",ok)
 if not ok: failures.append(label)
func run():
 var factory=load("res://scripts/combat/combat_factory.gd")
 var unit=factory.enemy_units("cassien_encounter")[0]
 var actor=load("res://scenes/ui/battlefield_actor.tscn").instantiate()
 root.add_child(actor)
 actor.setup(unit,false)
 var art=actor.cassien_art as AnimatedSprite2D
 check(art.visible and not actor.visual.visible,"authored sprite")
 check(art.sprite_frames.get_animation_names().size()==7,"all seven clips")
 for clip in art.sprite_frames.get_animation_names():
  check(art.sprite_frames.get_frame_count(clip)==8,"eight frames "+str(clip))
  check(art.sprite_frames.get_animation_loop(clip)==(clip==&"idle"),"loop policy "+str(clip))
  for i in range(8):
   if art.sprite_frames.get_frame_texture(clip,i).get_size()!=Vector2(128,128):
    failures.append("invalid frame size "+str(clip))
 for pair in [["cassien_sword_slash","attack"],["cassien_heavy_cleave","heavy_attack"],["cassien_crimson_crescent","crimson_crescent"],["cassien_crimson_requiem","crimson_requiem"]]:
  var ultimate: bool=pair[1]=="crimson_requiem"
  actor.play_cassien_action(pair[0],ultimate)
  check(art.animation==StringName(pair[1]),"route "+pair[0])
  var duration: float=actor.cassien_action_duration(pair[0],ultimate)
  check(actor.cassien_impact_time(pair[0],ultimate)<duration,"impact within clip "+pair[0])
  actor.take_hit()
  check(art.animation==StringName(pair[1]),"delayed hit preserves "+pair[1])
  await create_timer(duration+0.15).timeout
  check(art.animation==&"idle" and art.is_playing(),"recovery "+pair[1])
 actor.take_hit()
 check(art.animation==&"hit","hit reaction while idle")
 await create_timer(1.0).timeout
 check(art.animation==&"idle","hit recovery")
 actor.play_cassien_action("cassien_crimson_requiem",true)
 actor.play_death()
 actor.take_hit()
 check(actor.dead and art.animation==&"defeat","defeat overrides attack and hit")
 await create_timer(3.0).timeout
 check(art.animation==&"defeat" and art.frame==7 and not art.is_playing(),"final pose held")
 actor.queue_free()
 await process_frame
 print("CASSIEN COMBAT RESULT ",failures)
 quit(0 if failures.is_empty() else 1)
