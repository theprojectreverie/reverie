extends SceneTree
func _initialize():call_deferred("_run")
func xf(n:Node2D)->Transform2D:
 var t=n.transform
 var p=n.get_parent()
 while p is Node2D:
  t=p.transform*t
  p=p.get_parent()
 return t
func _run():
 for f in DirAccess.get_files_at("res://scenes/world/six_zone_reverie/individual_zones"):
  if not f.ends_with("_standalone.tscn"):continue
  var z=load("res://scenes/world/six_zone_reverie/individual_zones/"+f).instantiate()
  print("ZONE ",z.name)
  for l in z.find_children("*","TileMapLayer",true,false):
   if l.get_used_cells().is_empty():continue
   var lo=Vector2(INF,INF)
   var hi=-lo
   var t=xf(l)
   for c in l.get_used_cells():
    var p=t*l.map_to_local(c)
    var q=Vector2(p.x/64+p.y/32,-p.x/64+p.y/32)
    lo=lo.min(q)
    hi=hi.max(q)
   print(z.get_path_to(l)," count ",l.get_used_cells().size()," tiles ",l.tile_set.tile_size," transform ",t," iso ",lo," .. ",hi)
  for m in z.get_node("TransferPoints").get_children():
   if m is Marker2D: print(m.name," ",m.position)
  z.free()
 quit()
