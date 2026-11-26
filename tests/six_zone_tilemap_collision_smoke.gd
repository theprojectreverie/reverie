extends SceneTree
## Regression check for the authored standalone maps. Does not write save data.
const BASE = "res://scenes/world/six_zone_reverie/"
var failures: Array[String] = []

func _initialize() -> void:
 call_deferred("_run")

func check(ok: bool, message: String) -> void:
 if not ok:
  failures.append(message)
  printerr("FAIL: ", message)

func _run() -> void:
 var zones := ["01_royal_gardens","02_royal_gate","03_willow_fields","04_elderwood_grove","05_forsaken_ruins","06_ruined_tower"]
 var expected := [1308,10000,9999,10000,10000,9999]
 for i in zones.size():
  var packed := load(BASE+"zone_"+zones[i]+".tscn") as PackedScene
  check(packed!=null,zones[i]+" scene loads")
  if packed==null:continue
  var zone := packed.instantiate()
  var ground_name := "EditableGroundTileMap" if i==0 else "EditableTileMap"
  var ground := zone.find_child(ground_name,true,false) as TileMapLayer
  check(ground!=null,zones[i]+" ground layer exists")
  if ground!=null:
   check(ground.get_used_cells().size()>=expected[i],zones[i]+" retains terrain")
   var origin := ground.map_to_local(Vector2i.ZERO)
   var cursor: Node = ground
   while cursor!=zone:
    if cursor is Node2D:origin+=cursor.position
    cursor=cursor.get_parent()
   for label in ["EditableRoads","EditableWater","EditableVegetation","EditableWalls","EditablePathBorders"]:
    var layer := zone.get_node_or_null(label) as TileMapLayer
    check(layer!=null and layer.tile_set!=null,zones[i]+"/"+label+" palette")
    if layer==null or layer.tile_set==null:continue
    check(layer.tile_set.tile_size==Vector2i(64,32),zones[i]+"/"+label+" tile size")
    var cell := layer.local_to_map(origin-layer.position)
    check((layer.map_to_local(cell)+layer.position).is_equal_approx(origin),zones[i]+"/"+label+" grid alignment")
  zone.free()
  print("CHECKED ",zones[i])
 await _test_physics()
 print("SIX_ZONE_TILEMAP_COLLISION_SMOKE ", "PASS" if failures.is_empty() else "FAIL"," failures=",failures.size())
 quit(0 if failures.is_empty() else 1)

func _test_physics() -> void:
 var sandbox := Node2D.new()
 root.add_child(sandbox)
 var water := TileMapLayer.new()
 water.tile_set=load(BASE+"tilemaps/water_tileset.tres")
 sandbox.add_child(water)
 water.set_cell(Vector2i(0,0),0,Vector2i.ZERO)
 water.set_cell(Vector2i(8,8),1,Vector2i.ZERO)
 var walls := TileMapLayer.new()
 walls.tile_set=load(BASE+"tilemaps/gothic_walls_tileset.tres")
 walls.position=Vector2(1000,0)
 sandbox.add_child(walls)
 var wall_source := walls.tile_set.get_source(0) as TileSetScenesCollectionSource
 var wall_id := _scene_id(wall_source,"gothic_wall_corner_1x1.tscn")
 check(wall_id>=0,"wall corner prefab available")
 if wall_id>=0:walls.set_cell(Vector2i.ZERO,0,Vector2i.ZERO,wall_id)
 var trees := TileMapLayer.new()
 trees.tile_set=load(BASE+"tilemaps/garden_vegetation_tileset.tres")
 trees.position=Vector2(2000,0)
 sandbox.add_child(trees)
 var tree_source := trees.tile_set.get_source(0) as TileSetScenesCollectionSource
 var tree_id := _scene_id(tree_source,"tree_oak_01.tscn")
 check(tree_id>=0,"oak prefab available")
 if tree_id>=0:trees.set_cell(Vector2i.ZERO,0,Vector2i.ZERO,tree_id)
 for i in range(5):await physics_frame
 await process_frame
 var space := sandbox.get_world_2d().direct_space_state
 check(not _blocked(space,water.to_global(water.map_to_local(Vector2i.ZERO))),"visual water stays passable")
 check(_blocked(space,water.to_global(water.map_to_local(Vector2i(8,8)))),"solid water blocks player collision mask")
 check(_blocked(space,walls.to_global(walls.map_to_local(Vector2i.ZERO))),"painted wall preserves collision")
 check(_blocked(space,trees.to_global(trees.map_to_local(Vector2i.ZERO))),"painted oak preserves trunk collision")
 print("PHYSICS: visual water, solid water, wall and oak checked")
 sandbox.queue_free()
 await process_frame

func _scene_id(source: TileSetScenesCollectionSource, file: String) -> int:
 for i in source.get_scene_tiles_count():
  var id := source.get_scene_tile_id(i)
  if source.get_scene_tile_scene(id).resource_path.ends_with(file):return id
 return -1

func _blocked(space: PhysicsDirectSpaceState2D, pos: Vector2) -> bool:
 var q := PhysicsPointQueryParameters2D.new()
 q.position=pos
 q.collision_mask=1
 q.collide_with_bodies=true
 q.collide_with_areas=false
 return not space.intersect_point(q).is_empty()