extends SceneTree

func _initialize() -> void:
 call_deferred("_run")

func _run() -> void:
 var playable := (load("res://scenes/world/castle_royal_gardens.tscn") as PackedScene).instantiate()
 root.add_child(playable)
 await process_frame
 var live_terrain := playable.get_node("Terrain") as Node2D
 var live_edges := playable.get_node("Terrain/TerrainTransitions/RoadEdgeTransitions/NewAssetRoadEdges") as Node2D
 var live_path_system := playable.get_node("PathwayTiles") as Node2D
 var live_roads := playable.get_node("PathwayTiles/HandDesignedRoadSurfaces") as Node2D
 var live_castle := playable.get_node("RoyalCastleArchitecture") as Node2D
 var live_collection := playable.get_node("RoyalCastleArchitecture/CastleCollection") as Node2D
 var live_keep := live_collection.get_node("CastleKeep") as Node2D
 var live_road_z := live_path_system.z_index + live_roads.z_index
 assert(live_terrain.z_index == -20)
 assert(live_edges.z_index == -19 and not live_edges.z_as_relative)
 assert(live_path_system.z_index == 10 and live_roads.z_index == -28)
 assert(live_road_z == -18)
 assert(live_terrain.z_index < live_edges.z_index and live_edges.z_index < live_road_z,
  "Playable draw order must be ground, road-edge transition, cobblestone surface")
 assert(live_collection.get_child_count() == 1, "Only one complete palace silhouette may be mounted")
 assert(is_equal_approx(live_keep.scale.x, 1.42))
 assert(is_equal_approx(live_castle.global_scale.x, 1.65))
 print("PLAYABLE_LAYER_ORDER=", live_terrain.z_index, "<", live_edges.z_index, "<", live_road_z)
 print("CASTLE_COLLECTION_CHILDREN=", live_collection.get_child_count(), " KEEP_SCALE=", live_keep.scale)
 print("ROYAL_GARDEN_RENDER_LAYER_QA_OK")
 quit(0)
