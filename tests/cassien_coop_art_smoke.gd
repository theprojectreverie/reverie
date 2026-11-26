extends SceneTree
func _initialize():
 call_deferred("run")
func run():
 var panel=load("res://scenes/ui/components/coop_cassien_battle.tscn").instantiate()
 root.add_child(panel)
 await process_frame
 var art=panel.art
 assert(art.animation==&"idle" and art.is_playing())
 panel.apply_state(500.0,true,false)
 assert(art.animation==&"idle")
 panel.apply_state(400.0,true,true)
 assert(art.animation==&"hit")
 await art.animation_finished
 await process_frame
 assert(art.animation==&"attack")
 await art.animation_finished
 await process_frame
 assert(art.animation==&"idle")
 panel.apply_state(400.0,true,true)
 assert(art.animation==&"idle")
 panel.apply_state(400.0,true,true,"Crimson Crescent")
 assert(art.animation==&"crimson_crescent")
 await art.animation_finished
 await process_frame
 panel.apply_state(400.0,true,true,"Crimson Requiem")
 assert(art.animation==&"crimson_requiem")
 await art.animation_finished
 await process_frame
 assert(art.animation==&"idle")
 print("SPECIAL PLAYBACK PASS")
 panel.apply_state(300.0,false,true)
 assert(art.animation==&"hit")
 panel.apply_state(0.0,false,true)
 assert(art.animation==&"defeat")
 await art.animation_finished
 await process_frame
 assert(art.frame==7 and not art.is_playing())
 print("COOP LIVE HIT COUNTER DEFEAT PASS")
 panel.queue_free()
 await process_frame
 panel=load("res://scenes/ui/components/coop_cassien_battle.tscn").instantiate()
 root.add_child(panel)
 await process_frame
 panel.apply_state(0.0,false,false)
 assert(panel.art.animation==&"defeat" and panel.art.frame==7 and not panel.art.is_playing())
 print("COOP SNAPSHOT FINAL POSE PASS")
 panel.queue_free()
 await process_frame
 quit(0)
