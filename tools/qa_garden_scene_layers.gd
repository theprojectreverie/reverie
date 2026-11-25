extends Node

func _ready() -> void:
 call_deferred("_run")

func _run() -> void:
 var session = GameState.session_domain
 session.set_player_region("castle_royal_gardens")
 session.set_active_world("castle_royal_gardens")
 session.has_player_position = false
 session.region_positions.clear()
 var world := (load("res://scenes/world/castle_royal_gardens.tscn") as PackedScene).instantiate()
 add_child(world)
 await get_tree().process_frame
 await get_tree().process_frame
 var counts := {"Sprite2D":0,"Polygon2D":0,"TileMapLayer":0,"TileMap":0,"Node2D":0}
 var names: Array[String] = []
 _walk(world, counts, names)
 print("GARDEN_RENDER_NODE_COUNTS=", counts)
 print("LANDMARK_NODES:")
 for line in names:
  print(line)
 var terrain := world.get_node("Terrain") as Node2D
 print("TERRAIN_CHILDREN=", _children(terrain))
 print("WORLD_CHILDREN=", _children(world))
 print("EXPANSION_CHILDREN=", _children(world.get_node("ExpansionBuilder")))
 print("ROAD_CHILDREN=", _children(world.get_node("PathwayTiles/HandDesignedRoadSurfaces")))
 print("CASTLE_CHILDREN=", _children(world.get_node("RoyalCastleArchitecture/CastleCollection")))
 get_tree().quit()

func _walk(node: Node, counts: Dictionary, names: Array[String]) -> void:
 if node is Sprite2D: counts["Sprite2D"] += 1
 if node is Polygon2D: counts["Polygon2D"] += 1
 if node is TileMapLayer: counts["TileMapLayer"] += 1
 if node is TileMap: counts["TileMap"] += 1
 if node is Node2D: counts["Node2D"] += 1
 var low := str(node.name).to_lower()
 if "fountain" in low or "castle" in low or "terrain" in low or "map" in low or "promenade" in low:
  var detail := str(node.get_path())
  if node is Node2D:
   detail += " global=" + str((node as Node2D).global_position) + " visible=" + str((node as Node2D).is_visible_in_tree())
  names.append(detail)
 for child in node.get_children():
  _walk(child, counts, names)

func _children(node: Node) -> Array[String]:
 var result: Array[String] = []
 for child in node.get_children():
  result.append("%s [%s]" % [child.name, child.get_class()])
 return result
