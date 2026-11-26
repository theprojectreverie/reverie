extends SceneTree
var failures: Array[String]=[]
func _initialize():
 call_deferred("_run")
func _run():
 var v=load("res://scenes/world/village/imported_village/village.tscn").instantiate()
 v.position=Vector2.ZERO
 root.add_child(v)
 for i in range(5):await physics_frame
 var space=v.get_world_2d().direct_space_state
 var footprints=v.get_node("BuildingFootprints")
 var hits=0
 for c in footprints.get_children():
  if blocked(space,c.global_position):hits+=1
 if hits!=18:failures.append("building footprint count")
 print("BUILDINGS ",hits,"/18 physically solid")
 for label in ["trees","fences and borders"]:
  var layer=v.get_node(label) as TileMapLayer
  var solid=0
  var tested=0
  var hit=0
  for cell in layer.get_used_cells():
   var td=layer.get_cell_tile_data(cell)
   if td==null or td.get_collision_polygons_count(0)==0:continue
   solid+=1
   if tested<120:
    tested+=1
    if blocked(space,layer.to_global(layer.map_to_local(cell))):hit+=1
  print(label," solid cells=",solid," sampled hits=",hit,"/",tested)
  if solid==0 or hit!=tested:failures.append(label+" collision samples")
 for point in [Vector2(-2090,112),Vector2(1200,65),v.get_node("GeraldBossSpawn").global_position]:
  var b=blocked(space,point)
  print("CLEARANCE ",point," blocked=",b)
  if b:failures.append("blocked landmark "+str(point))
 v.queue_free()
 await process_frame
 print("VILLAGE COLLISION FAILURES ",failures)
 quit(0 if failures.is_empty() else 1)
func blocked(space:PhysicsDirectSpaceState2D,point:Vector2)->bool:
 var query=PhysicsPointQueryParameters2D.new()
 query.position=point
 query.collision_mask=1
 return not space.intersect_point(query).is_empty()