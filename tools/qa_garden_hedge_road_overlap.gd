extends Node

func _ready() -> void:
 call_deferred("_run")

func _run() -> void:
 var game_state: Node = get_node("/root/GameState")
 var state = game_state.get("session_domain")
 state.set_player_region("castle_royal_gardens")
 state.set_active_world("castle_royal_gardens")
 state.has_player_position = false
 state.region_positions.clear()
 var world := (load("res://scenes/world/castle_royal_gardens.tscn") as PackedScene).instantiate()
 add_child(world)
 await get_tree().process_frame
 await get_tree().process_frame
 var roads := world.get_node("PathwayTiles/HandDesignedRoadSurfaces")
 var markers := world.get_node("ExpansionBuilder/ApproachPlacements")
 var failed := 0
 var hedge_count := 0
 for marker in markers.get_children():
  if not (marker is Marker2D) or not str(marker.name).begins_with("Hedge_"): continue
  hedge_count += 1
  var grid: Vector2 = marker.get_meta("grid_position")
  var global_pos: Vector2 = markers.to_global(IsoMath.grid_to_world(grid.x, grid.y))
  var blocked := _near_road(roads, global_pos, 160.0)
  print("HEDGE_PERIMETER ", marker.name, " grid=", grid, " road_clearance_160=", not blocked)
  if blocked: failed += 1
 if hedge_count != 4: failed += 1
 print("HEDGE_PERIMETER_CLEARANCE=", hedge_count - failed, "/", hedge_count)
 if failed == 0:
  print("HEDGE_PERIMETER_CLEARANCE_OK")
 else:
  push_error("HEDGE_PERIMETER_CLEARANCE_FAILED count=%d" % failed)
 get_tree().quit(0 if failed == 0 else 1)

func _near_road(roads: Node, global_pos: Vector2, margin: float) -> bool:
 for road in roads.get_children():
  if not (road is Polygon2D): continue
  var p: Vector2 = road.to_local(global_pos)
  var poly: PackedVector2Array = road.polygon
  if Geometry2D.is_point_in_polygon(p, poly): return true
  for i in range(poly.size()):
   var closest := Geometry2D.get_closest_point_to_segment(p, poly[i], poly[(i+1)%poly.size()])
   if p.distance_to(closest) < margin: return true
 return false
