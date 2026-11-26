extends SceneTree
func _initialize():call_deferred("_run")
func _run():
 var t=Time.get_ticks_msec()
 var s=load("res://scenes/world/village/imported_village/village.tscn")
 print("VILLAGE LOAD MS ",Time.get_ticks_msec()-t)
 t=Time.get_ticks_msec()
 var v=s.instantiate()
 print("VILLAGE INSTANTIATE MS ",Time.get_ticks_msec()-t)
 for l in v.find_children("*","TileMapLayer",true,false):
  var ts=l.tile_set
  if ts==null:continue
  var cells=l.get_used_cells()
  var phys=0
  for c in cells:
   var td=l.get_cell_tile_data(c)
   if td:
    for i in ts.get_physics_layers_count():
     if td.get_collision_polygons_count(i)>0:phys+=1;break
  print("LAYER ",l.name," count=",cells.size()," physical=",phys," ysort=",l.y_sort_enabled," quad=",l.rendering_quadrant_size," nav=",ts.get_navigation_layers_count()," occ=",ts.get_occlusion_layers_count())
 t=Time.get_ticks_msec()
 root.add_child(v)
 print("VILLAGE ADD MS ",Time.get_ticks_msec()-t)
 t=Time.get_ticks_msec()
 await process_frame
 await process_frame
 print("VILLAGE READY MS ",Time.get_ticks_msec()-t)
 v.queue_free()
 await process_frame
 quit()
