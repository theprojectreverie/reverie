extends SceneTree
var failures=0
func _initialize():
 call_deferred("run")
func check(ok:bool,label:String):
 print(label," = ",ok)
 if not ok: failures+=1
func run():
 if OS.get_environment("REVERIE_E2E_DISABLE_LOCAL_SAVE")!="1":
  quit(2)
  return
 root.get_node("GameState").new_game("Cassien QA")
 var battle=load("res://scenes/ui/combat_screen.tscn").instantiate()
 battle.group_id="cassien_encounter"
 root.add_child(battle)
 for i in range(120):
  await process_frame
  if battle.engine!=null and battle._battlefield.actors().size()>1:break
 battle._turn_token+=1
 await create_timer(2.3).timeout
 battle._auto=false
 var boss=battle.engine.combatants[-1]
 var party=battle.engine.living(0)
 battle.engine.current_actor_index=party[0].combat_index
 for e in [0.0,92.0,100.0]:
  boss.energy=e
  battle._hud_component.refresh_cards()
  battle._hud_component.refresh_skills()
  var label=battle._boss_phase_label.text
  print("HUD ",label," HINT ",battle._hint_label.text)
  check(label.contains("Requiem"),"charge label")
  if e==92:check(battle._hint_label.text.contains("Consider Defend"),"near-full warning")
  if e==100:check(label.contains("READY") and battle._hint_label.text.contains("Defend to reduce damage"),"ready warning")
 battle._update_turn_order()
 await process_frame
 var found=false
 for slot in battle._turn_box.get_children():
  for item in slot.get_children():
   if item.tooltip_text==boss.display_name:
    found=item.portrait_texture!=null and item.portrait_texture.resource_path.ends_with("/profile/cassien_mythic.png")
 check(found,"authored turn portrait")
 var actor=battle._actor_for_uid(boss.uid)
 actor.set_intent("Crimson Requiem")
 check(actor.get_node("NameLabel").position.y+actor.home_position.y+actor.get_node("NameLabel").size.y<=battle._battlefield.size.y,"boss name within battlefield")
 if DisplayServer.get_name()!="headless":
  await RenderingServer.frame_post_draw
  root.get_texture().get_image().save_png(OS.get_environment("TEMP")+"/cassien_hud_review.png")
 battle.queue_free()
 for i in range(3): await process_frame
 root.get_node("AudioDirector").stop_all_audio_immediately()
 await create_timer(0.5).timeout
 print("CASSIEN HUD FAILURES=",failures)
 quit(0 if failures==0 else 1)
