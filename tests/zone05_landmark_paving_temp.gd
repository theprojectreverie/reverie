extends SceneTree
const MAP="res://scenes/world/six_zone_reverie/tilemaps/05_forsaken_ruins_tilemap.tscn"
func _initialize():
 call_deferred("_run")
func _iso(p:Vector2)->Vector2:
 return Vector2(p.x/64.0+p.y/32.0,-p.x/64.0+p.y/32.0)
func _on_path(p:Vector2,route:Array)->bool:
 var q=_iso(p)
 for i in range(route.size()-1):
  var a=_iso(route[i])
  var b=_iso(route[i+1])
  var lo=Vector2(minf(a.x,b.x),minf(a.y,b.y))-Vector2.ONE*1.35
  var hi=Vector2(maxf(a.x,b.x),maxf(a.y,b.y))+Vector2.ONE*1.35
  if q.x>=lo.x and q.x<=hi.x and q.y>=lo.y and q.y<=hi.y:
   return true
 return false
func _run():
 var layer=load(MAP).instantiate() as TileMapLayer
 root.add_child(layer)
 var pads=[[Vector2(-300,830),256.0,128.0],[Vector2(1380,1190),320.0,160.0],[Vector2(-650,2390),320.0,160.0],[Vector2(420,2710),192.0,96.0]]
 var paths=[
 [Vector2(-700,1630),Vector2(300,1130),Vector2(-210,875)],
 [Vector2(240,1688),Vector2(1056,1280),Vector2(1296,1400),Vector2(1496,1300)],
 [Vector2(-172,1894),Vector2(-904,2260),Vector2(-680,2372)],
 [Vector2(880,2008),Vector2(-52,2474),Vector2(420,2710)]
 ]
 var changed=0
 for cell in layer.get_used_cells():
  var p=layer.to_global(layer.map_to_local(cell))
  var old=layer.get_cell_source_id(cell)
  if old==20 or old==25:
   continue
  var id=old
  for route in paths:
   if _on_path(p,route):
    id=20
    break
  for pad in pads:
   var rel=p-Vector2(pad[0])
   if absf(rel.x)/float(pad[1])+absf(rel.y)/float(pad[2])<=1.0:
    id=25
    break
  if id!=old:
   layer.set_cell(cell,id,Vector2i.ZERO,0)
   changed+=1
 var pack=PackedScene.new()
 assert(pack.pack(layer)==OK)
 assert(ResourceSaver.save(pack,MAP)==OK)
 print("LANDMARK PAVING SAVED ",changed," cells; map remains ",layer.get_used_cells().size()," tiles")
 layer.queue_free()
 quit()
