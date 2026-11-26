extends SceneTree
const MAP="res://scenes/world/six_zone_reverie/tilemaps/05_forsaken_ruins_tilemap.tscn"
func _initialize():
 call_deferred("_run")
func _run():
 var layer=load(MAP).instantiate() as TileMapLayer
 root.add_child(layer)
 var corners=[Vector2(300,1130),Vector2(1056,1280),Vector2(1296,1400),Vector2(-904,2260),Vector2(-52,2474)]
 var bevels:Array[Vector2i]=[]
 for c in layer.get_used_cells():
  if layer.get_cell_source_id(c)!=24:
   continue
  var p=layer.to_global(layer.map_to_local(c))
  var nearby=false
  for corner in corners:
   if p.distance_to(corner)<112.0:
    nearby=true
    break
  if not nearby:
   continue
  var adjacent=[]
  for n in layer.get_surrounding_cells(c):
   if layer.get_cell_source_id(n)==20:
    adjacent.append(layer.map_to_local(n)-layer.map_to_local(c))
  if adjacent.size()==2 and (adjacent[0]+adjacent[1]).length()>1.0:
   bevels.append(c)
  elif adjacent.size()>=3:
   bevels.append(c)
 for c in bevels:
  layer.set_cell(c,20,Vector2i.ZERO,0)
 var packed=PackedScene.new()
 assert(packed.pack(layer)==OK)
 assert(ResourceSaver.save(packed,MAP)==OK)
 print("CORNER TILE ADJUSTMENTS ",bevels.size(),"; base count ",layer.get_used_cells().size())
 layer.queue_free()
 await process_frame
 quit()
