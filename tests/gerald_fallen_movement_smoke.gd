extends SceneTree
func _initialize():
 call_deferred("run")
func run():
 var gs=root.get_node("GameState")
 gs.quest_domain.flags["tutorial_complete"]=true
 gs.quest_domain.flags.erase("village_gerald_defeated")
 gs.quest_domain.flags.erase("village_gerald_backstory_pending")
 change_scene_to_file("res://scenes/world/village/imported_village/village_playable.tscn")
 await scene_changed
 for i in range(5): await physics_frame
 var z=current_scene
 var g=z.get_node("VillageMap/GeraldBossSpawn/GeraldChallenge")
 var p=z.get("checkpoint_player")
 var start: Vector2=g.global_position
 var names=["e","se","s","sw","w","nw","n","ne"]
 var ok=true
 for i in range(8):
  var direction=Vector2.RIGHT.rotated(i*PI/4)
  ok=ok and g.walk_clip_for_direction(direction)==StringName("walk_"+names[i])
 p.global_position=start+Vector2(0,88)
 p.input_enabled=false
 g.engaged=true
 var cam=p.get_node("Camera2D") as Camera2D
 cam.reset_smoothing()
 for i in range(8): await physics_frame
 if DisplayServer.get_name()!="headless":
  await RenderingServer.frame_post_draw
  root.get_texture().get_image().save_png("user://gerald_approach_before.png")
 var audio=root.get_node("AudioDirector")
 audio._last_sfx_variant.erase("dirt_step")
 g._walk_toward_player(p.global_position)
 for i in range(12): await physics_frame
 var walk=g.get_node("FallenWalk")
 var moving=walk.visible and walk.is_playing() and g.global_position.distance_to(start)>0
 print("WALK_ACTIVE=",moving," clip=",walk.animation)
 if DisplayServer.get_name()!="headless":
  await RenderingServer.frame_post_draw
  root.get_texture().get_image().save_png("user://gerald_approach_during.png")
 for i in range(120): await physics_frame
 var settled=not walk.visible and g.get_node("FallenIdle").visible and absf(g.global_position.distance_to(start)-32.0)<0.5
 if DisplayServer.get_name()!="headless":
  await RenderingServer.frame_post_draw
  root.get_texture().get_image().save_png("user://gerald_approach_after.png")
 print("WALK_SETTLED=",settled," moved=",g.global_position.distance_to(start))
 # Repeat a challenge from farther south: Gerald must not drift.
 p.global_position=g.global_position+Vector2(0,88)
 await g._walk_toward_player(p.global_position)
 var bounded=g.global_position.distance_to(start)<=32.1 and not walk.visible
 var facing=g.get_node("FallenIdle").animation==&"idle_front"
 print("RETRY_BOUNDED=",bounded," FACING=",facing)
 var steps=int(audio._last_sfx_variant.get("dirt_step",0))>0
 print("WORLD_FOOTSTEPS=",steps)
 ok=ok and steps
 print("GERALD_MOVEMENT_PASS=",ok and moving and settled and bounded and facing)
 quit(0 if ok and moving and settled and bounded and facing else 1)
