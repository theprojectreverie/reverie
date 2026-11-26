extends SceneTree
func _initialize():
 call_deferred("_run")
func _run():
 if OS.get_environment("REVERIE_E2E_DISABLE_LOCAL_SAVE")!="1":
  quit(2)
  return
 for id in ["gerald","gerald_common","gerald_epic","gerald_legendary","gerald_mythic"]:
  var source=SpriteFramesActorSource.from_playable(id)
  var errors=source.validate_sheets()
  assert(errors.is_empty(),str(id)+": "+str(errors.slice(0,5)))
  assert(source.source_label().ends_with("world_sheet_fallen.tres"))
  assert(source.frame_count(0,0)==4 and source.frame_count(1,1)==16 and source.frame_count(4,2)==16 and source.frame_count(5,2)==8 and source.frame_count(7,2)==14)
 var gs=root.get_node("GameState")
 gs.quest_domain.flags["tutorial_complete"]=true
 gs.quest_domain.flags["village_gerald_defeated"]=true
 gs.quest_domain.flags["six_zone_checkpoint"]={"zone":"StandaloneZone05"}
 change_scene_to_file("res://scenes/world/six_zone_reverie/individual_zones/zone_05_forsaken_ruins_standalone.tscn")
 await scene_changed
 for i in range(8): await process_frame
 var zone=current_scene
 var player=zone.checkpoint_player
 assert(player.available_avatars().has("gerald"))
 player.set_avatar("gerald")
 assert(player.avatar_id=="gerald")
 player.input_enabled=false
 var v=player.visual
 assert(v.character_art_report().has_frames and v.animator.gerald_fallen_frames)
 for d in range(8):
  for state in [0,1,2,4,5,7,8]:
   v.animator.play_forced(state,d)
   v._update_sprite_frame()
   assert(v._sprite.texture.get_width()==128)
   assert(v._sprite.texture.atlas.resource_path.contains("gerald_fallen") or v._sprite.texture.atlas.resource_path.contains("walk_review"))
   assert(v.animator.frame_count()==v.frame_source.frame_count(state,d))
   assert(is_equal_approx(v.animator.fps(),v.frame_source.fps(state)))
 v.animator.play_forced(0,0)
 v._update_sprite_frame()
 print("PLAYABLE GERALD ALL 8 DIRECTIONS AND COMBAT CLIPS PASS")
 if DisplayServer.get_name()!="headless":
  for i in range(5):await process_frame
  await RenderingServer.frame_post_draw
  print("CAPTURE ",root.get_texture().get_image().save_png("C:/Users/quoth/Downloads/reverie_gerald_playable_review.png"))
 var combat=load("res://scenes/ui/battlefield_actor.tscn").instantiate()
 zone.add_child(combat)
 var units=load("res://scripts/combat/combat_factory.gd").player_units()
 var g
 for unit in units:
  if unit.def_id=="gerald":g=unit
 assert(g!=null)
 combat.setup(g,true)
 assert(combat.visual.animator.gerald_fallen_frames and combat.visual.character_art_report().has_frames)
 combat.play_attack()
 assert(combat.visual.animator.state==4 or combat.visual.animator.state==8)
 print("PARTY GERALD NEW ART PASS")
 combat.queue_free()
 zone.queue_free()
 for i in range(3):await process_frame
 root.get_node("AudioDirector").stop_all_audio_immediately()
 await create_timer(0.35).timeout
 quit()
