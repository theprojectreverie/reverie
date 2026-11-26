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
 for i in range(10):await physics_frame
 var zone=current_scene
 var player=zone.checkpoint_player
 var shape=CircleShape2D.new()
 shape.radius=12
 var query=PhysicsShapeQueryParameters2D.new()
 query.shape=shape
 query.collision_mask=1
 var ground=zone.get_node("Zone/GroundTiles/EditableTileMap")
 var pts=[Vector2(-968,1130),Vector2(-908,1196),Vector2(-780,1260),Vector2(-650,1390),Vector2(-100,1500),Vector2(100,1550),Vector2(850,1980),Vector2(1030,2050),Vector2(1568,2352),Vector2(1664,2432)]
 for i in range(pts.size()-1):
  var a:Vector2=pts[i]
  var b:Vector2=pts[i+1]
  query.transform=Transform2D(0,a)
  query.motion=b-a
  var result=player.get_world_2d().direct_space_state.cast_motion(query)
  var missing=0
  for j in range(21):
   var point=a.lerp(b,j/20.0)
   if ground.get_cell_source_id(ground.local_to_map(ground.to_local(point)))<0:missing+=1
  print("PATH ",a," to ",b," cast=",result," ground missing=",missing)
 var added=gs.roster_domain.add_character("ravienna")
 assert(gs.roster_domain.set_party([added.instance.uid]))
 assert(player.available_avatars().has("ravienna"))
 player.set_avatar("ravienna")
 assert(player.avatar_id=="ravienna" and not player.visual.using_temporary_art)
 var source=player.visual.frame_source
 assert(source.validate_sheets().is_empty())
 for d in range(8):
  assert(source.frame_count(1,d)==16)
  player.visual.animator.play_forced(1,d)
  player.visual.animator.tick(0.3)
  assert(player.visual.animator.frame>0)
 print("PLAYABLE REVIENNA EIGHT DIRECTIONS AND ASSET VALIDATION PASS")
 current_scene.queue_free()
 for i in range(12):await process_frame
 root.get_node("AudioDirector").stop_all_audio_immediately()
 await create_timer(0.35).timeout
 quit()
