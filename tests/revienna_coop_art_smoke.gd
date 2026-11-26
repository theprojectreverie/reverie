extends SceneTree
func _initialize():call_deferred("_run")
func _run():
 var panel=load("res://scenes/ui/components/coop_revienna_battle.tscn").instantiate()
 root.add_child(panel)
 for i in range(5):await process_frame
 var art=panel.art
 assert(art.animation==&"idle" and art.is_playing())
 panel.apply_state(1600.0,true,false)
 assert(art.animation==&"idle")
 panel.apply_state(1500.0,true,true)
 assert(art.animation==&"hit")
 await art.animation_finished
 await process_frame
 assert(art.animation==&"corruption_bolt")
 await create_timer(0.7).timeout
 assert(is_instance_valid(panel._bolt))
 await art.animation_finished
 await process_frame
 assert(art.animation==&"idle")
 await create_timer(0.3).timeout
 assert(not is_instance_valid(panel._bolt))
 for pair in [["Corruption Bolt","corruption_bolt"],["Shadow Lash","shadow_lash"],["Hollow Wail","hollow_wail"]]:
  panel.apply_state(1400.0,true,true,pair[0],2)
  assert(str(art.animation)==pair[1])
  await art.animation_finished
  await process_frame
  assert(art.animation==&"idle")
 print("COOP HIT, COUNTER, PROJECTILE AND THREE AUTHORED SPECIALS PASS")
 var warning={"name":"Eclipse Verdict","resolveAt":12345,"targetId":"local"}
 panel.apply_state(400.0,false,true,"",3,warning)
 assert(panel._eclipse_waiting and art.animation==&"ravienna_eclipse" and panel.corona.visible)
 await create_timer(1.7).timeout
 assert(art.frame==9 and not art.is_playing() and not panel.eruption.visible)
 panel.apply_state(400.0,false,false,"",3,warning)
 assert(art.frame==9 and panel._eclipse_waiting and not panel.eruption.visible)
 panel.apply_state(400.0,true,true,"Eclipse Verdict",3)
 assert(art.frame==10 and not panel._eclipse_waiting and panel.eruption.visible and panel.cracks.visible)
 await RenderingServer.frame_post_draw
 print("ECLIPSE CAPTURE ",root.get_texture().get_image().save_png("C:/Users/quoth/Downloads/reverie_coop_eclipse_review.png"))
 await art.animation_finished
 await create_timer(1.6).timeout
 assert(not panel.eruption.visible and not panel.cracks.visible and not panel.corona.visible)
 panel.apply_state(400.0,false,false,"",3,warning)
 assert(panel._eclipse_waiting and art.frame==9 and not panel.eruption.visible)
 panel.apply_state(400.0,false,false,"",3)
 assert(not panel._eclipse_waiting and art.animation==&"idle" and not panel.cracks.visible)
 print("ECLIPSE WINDUP HOLD, SERVER IMPACT, RECOVERY AND CLEANUP PASS")

 for i in range(20):panel.apply_state(1390.0-i*10,true,true,"",3)
 assert(panel._pending.size()<=3)
 panel.apply_state(1000.0,false,false)
 assert(panel._pending.is_empty() and art.animation==&"idle")
 panel.apply_state(0.0,false,true)
 assert(art.animation==&"defeat")
 await art.animation_finished
 await process_frame
 assert(art.frame==art.sprite_frames.get_frame_count(&"defeat")-1 and not art.is_playing())
 await RenderingServer.frame_post_draw
 print("CAPTURE ",root.get_texture().get_image().save_png("C:/Users/quoth/Downloads/reverie_coop_revienna_defeat.png"))
 panel.queue_free()
 await process_frame
 panel=load("res://scenes/ui/components/coop_revienna_battle.tscn").instantiate()
 root.add_child(panel)
 await process_frame
 panel.apply_state(0.0,false,false)
 assert(panel.art.animation==&"defeat" and not panel.art.is_playing() and panel.art.frame==panel.art.sprite_frames.get_frame_count(&"defeat")-1)
 print("BOUNDED QUEUE, RECONNECT AND FINAL DEFEAT POSE PASS")
 panel.queue_free()
 for i in range(5):await process_frame
 quit(0)
