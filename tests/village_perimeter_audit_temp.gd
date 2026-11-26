extends SceneTree
func _initialize():call_deferred("_run")
func _run():
 var v=load("res://scenes/world/village/imported_village/village_playable.tscn").instantiate()
 for name in ["grass","dirt","road"]:
  var l=v.get_node("VillageMap/"+name)
  var lo=Vector2(INF,INF)
  var hi=-lo
  var pts=PackedVector2Array()
  for c in l.get_used_cells():
   var p=l.position+l.map_to_local(c)
   lo=lo.min(p)
   hi=hi.max(p)
   pts.append(p)
  print(name," count ",pts.size()," size ",l.tile_set.tile_size," layout ",l.tile_set.tile_shape," bounds ",lo," ",hi," hull ",Geometry2D.convex_hull(pts))
 v.free()
 quit()
