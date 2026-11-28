extends SceneTree
func _initialize():call_deferred("run")
func run():
 var gs=root.get_node("GameState")
 gs.quest_domain.flags["tutorial_complete"]=true
 change_scene_to_file("res://scenes/world/six_zone_reverie/individual_zones/zone_05_forsaken_ruins_standalone.tscn")
 await scene_changed
 for i in range(5):await physics_frame
 var z=current_scene
 var dressing=z.get_node("CemeteryDressing")
 assert(dressing.get_child_count()==41)
 for prop in dressing.get_children():
  assert(prop.get_node("Artwork").texture!=null)
  assert(prop.get_node("Body").get_child_count()>0)
 var l:TileMapLayer=z.get_node("Zone/GroundTiles/EditableTileMap")
 var q=PhysicsShapeQueryParameters2D.new()
 q.shape=z.checkpoint_player.get_node("CollisionShape2D").shape
 q.collision_mask=1
 var space=z.get_world_2d().direct_space_state
 var blocked=[]
 for c in l.get_used_cells():
  if l.get_cell_source_id(c)==24:continue
  q.transform=Transform2D(0,l.to_global(l.map_to_local(c))+Vector2(0,-10))
  for hit in space.intersect_shape(q,20):
   if dressing.is_ancestor_of(hit.collider):blocked.append(c)
 assert(blocked.is_empty(),str(blocked))
 assert(z.get_node("RaviennaCourtyard/RaviennaStoneTomb/RitualAnimation").has_animation("awakening"))
 assert(z.get_node("CassienRitual").global_position==z.get_node("RaviennaCourtyard/WestEntrance").global_position)
 print("FORSAKEN CEMETERY PASS: ",dressing.get_child_count()," props, zero new blocked paved cells, original guard and ritual retained")
 z.queue_free()
 for i in range(3):await process_frame
 quit(0)
