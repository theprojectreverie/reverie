extends SceneTree
func _initialize():
 var packed = load("res://scenes/world/castle_gardens/components/castle_road_edge_transitions.tscn")
 var scene = packed.instantiate()
 var layer = scene.get_node("HandPaintedRoadEdgeTransitions") as TileMapLayer
 print("USED ", layer.get_used_cells().size())
 for cell in layer.get_used_cells():
  print("CELL ", cell, " ATLAS ", layer.get_cell_atlas_coords(cell), " SOURCE ", layer.get_cell_source_id(cell), " LOCAL ", layer.map_to_local(cell))
 quit()
