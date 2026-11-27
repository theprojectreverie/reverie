extends SceneTree
func _initialize():
 call_deferred("_run")
func _run():
 if OS.get_environment("REVERIE_E2E_DISABLE_LOCAL_SAVE")!="1":
  quit(2)
  return
 var gs=root.get_node("GameState")
 gs.quest_domain.flags["tutorial_complete"]=true
 change_scene_to_file("res://scenes/world/six_zone_reverie/individual_zones/zone_05_forsaken_ruins_standalone.tscn")
 await scene_changed
 for i in range(10): await physics_frame
 var zone=current_scene
 var player=zone.checkpoint_player
 var added=gs.roster_domain.add_character("mirene_legendary")
 assert(gs.roster_domain.set_party([added.instance.uid]))
 assert(player.available_avatars().has("mirene_legendary"))
 player.set_avatar("mirene_legendary")
 assert(player.avatar_id=="mirene_legendary" and not player.visual.using_temporary_art)
 var actions=[["move_down"],["move_down","move_right"],["move_right"],["move_up","move_right"],["move_up"],["move_up","move_left"],["move_left"],["move_down","move_left"]]
 var vectors=[Vector2.DOWN,Vector2(1,1).normalized(),Vector2.RIGHT,Vector2(1,-1).normalized(),Vector2.UP,Vector2(-1,-1).normalized(),Vector2.LEFT,Vector2(-1,1).normalized()]
 for sprint in [false,true]:
  for d in range(8):
   player.global_position=Vector2(-100,1500)
   player.velocity=Vector2.ZERO
   for i in range(4): await physics_frame
   var start:Vector2=player.global_position
   for action in actions[d]:Input.action_press(action)
   if sprint:Input.action_press("sprint")
   for i in range(24):await physics_frame
   assert(player.global_position.distance_to(start)>20)
   assert((player.global_position-start).normalized().dot(vectors[d])>0.92)
   assert(player.visual.animator.state==(2 if sprint else 1))
   assert(player.visual.animator.direction==d)
   assert(player.visual._sprite.visible and not player.visual.using_temporary_art)
   print("REAL INPUT ", "RUN" if sprint else "WALK"," direction ",d," moved ",player.global_position.distance_to(start))
   for action in actions[d]:Input.action_release(action)
   Input.action_release("sprint")
   for i in range(25):await physics_frame
   assert(player.visual.animator.state==0 and player.velocity.length()<1)
 var variant=gs.roster_domain.add_character("mirene_mythic")
 assert(gs.roster_domain.set_party([added.instance.uid,variant.instance.uid]))
 assert(player.avatar_component.cycle_avatar()=="mirene_mythic")
 assert(not player.visual.using_temporary_art)
 assert(player.avatar_component.cycle_avatar()=="mirene_legendary")
 print("REAL WALK/RUN, STOP AND AVATAR VARIANT SWITCH PASS")
 var player_ref=weakref(player)
 current_scene.queue_free()
 for i in range(15):await process_frame
 assert(player_ref.get_ref()==null)
 root.get_node("AudioDirector").stop_all_audio_immediately()
 await create_timer(1.5).timeout
 quit()
