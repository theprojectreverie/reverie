extends SceneTree
const SCENE="res://scenes/world/six_zone_reverie/individual_zones/zone_03_willow_fields_standalone.tscn"
var player: CharacterBody2D
var layer: TileMapLayer
var touch: Node
var offroad := 0
var walked := 0
var failed := false
func _initialize(): call_deferred("_run")
func _walk_to(target:Vector2, stop_on_transfer:bool=false)->bool:
 var steps=0
 var zone=current_scene
 while is_instance_valid(player) and player.global_position.distance_to(target)>13.0 and steps<2000:
  var diff=target-player.global_position
  touch.set_move_vector(diff.normalized()*clampf(diff.length()/45.0,0.25,0.88))
  await physics_frame
  if current_scene!=zone:
   touch.release()
   return stop_on_transfer and current_scene.name==&"StandaloneZone04"
  if not is_instance_valid(player):return false
  var id=layer.get_cell_source_id(layer.local_to_map(layer.to_local(player.global_position)))
  if id<=1:offroad+=1
  walked+=1
  steps+=1
 touch.release()
 for i in range(8):await physics_frame
 return is_instance_valid(player) and player.global_position.distance_to(target)<28.0
func _run():
 if OS.get_environment("REVERIE_E2E_DISABLE_LOCAL_SAVE")!="1":
  quit(2)
  return
 var gs=root.get_node("GameState")
 gs.quest_domain.flags["tutorial_complete"]=true
 gs.quest_domain.flags.erase("six_zone_checkpoint")
 touch=root.get_node("TouchInput")
 change_scene_to_file(SCENE)
 await scene_changed
 for i in range(8):await physics_frame
 var z=current_scene
 player=z.checkpoint_player
 layer=z.get_node("Zone/GroundTiles/EditableTileMap")
 assert(player.global_position.distance_to(Vector2(0,2168))<3)
 assert(layer.get_cell_source_id(layer.local_to_map(layer.to_local(player.global_position)))>1)
 print("FRESH ROAD SPAWN PASS")
 var bridge=z.get_node("Zone/WillowScenery/BridgeRiver")
 assert(bridge.z_index<player.z_index)
 Engine.time_scale=4.0
 for p in [Vector2(-560,2448),Vector2(-2318,1569),Vector2(-800,810),Vector2(-640,730),Vector2(-800,810),Vector2(900,1660),Vector2(1160,1588)]:
  if not await _walk_to(p):
   push_error("WALK FAILED "+str(p)+" at "+str(player.global_position))
   failed=true
   break
 if not failed:
  print("WESTERN LOOP AND WALK TO BRIDGE PASS ",player.global_position)
  if DisplayServer.get_name()!="headless":
   Engine.time_scale=1.0
   player.camera.reset_smoothing()
   for i in range(8):await physics_frame
   await RenderingServer.frame_post_draw
   print("BRIDGE GAMEPLAY CAPTURE ",root.get_texture().get_image().save_png("C:/Users/quoth/Downloads/reverie_willow_bridge_walk.png"))
   Engine.time_scale=4.0
  for p in [Vector2(1710,1313),Vector2(1896,1220),Vector2(2828,1686)]:
   if not await _walk_to(p):
    push_error("WALK FAILED "+str(p))
    failed=true
    break
 if not failed:
  assert(gs.quest_domain.quest_state("willow_crossing")=="complete")
  failed=not await _walk_to(Vector2(3008,1744),true)
 print("MOVEMENT TEST steps=",walked," offroad frames=",offroad," transition=",current_scene.name," failed=",failed)
 Engine.time_scale=1.0
 touch.release()
 if is_instance_valid(current_scene):current_scene.queue_free()
 for i in range(3):await process_frame
 root.get_node("AudioDirector").stop_all_audio_immediately()
 await create_timer(0.35).timeout
 quit(0 if not failed and offroad==0 else 1)
