extends SceneTree
func _initialize():call_deferred("run")
func run():
 if OS.get_environment("REVERIE_E2E_DISABLE_LOCAL_SAVE")!="1":quit(2);return
 root.get_node("GameState").quest_domain.flags["tutorial_complete"]=true
 change_scene_to_file("res://scenes/world/six_zone_reverie/individual_zones/zone_03_willow_fields_standalone.tscn")
 await scene_changed
 for i in range(8):await physics_frame
 var z=current_scene;var ground=z.get_node("Zone/GroundTiles/EditableTileMap");var errors=[];var total=0
 for n in z.get_node("Zone").find_children("*","Sprite2D",true,false):
  if not n.is_visible_in_tree() or not n.texture or n.z_index<0:continue
  total+=1
  if ground.get_cell_source_id(ground.local_to_map(ground.to_local(n.global_position)))<0:errors.append(str(z.get_path_to(n)))
 print("MAP BOUNDARY AUDIT ",total," sprite origins; outside=",errors)
 z.queue_free()
 for i in range(3):await process_frame
 root.get_node("AudioDirector").stop_all_audio_immediately()
 await create_timer(.35).timeout
 quit(0 if errors.is_empty() else 1)
