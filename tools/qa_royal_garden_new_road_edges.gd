extends SceneTree

const EDGE_SCENE := "res://scenes/world/castle_gardens/components/castle_road_edge_transitions.tscn"
const EXPECTED := {
 "NE": "res://assets/reverie_pack_v01/Royal_Gardens/Terrain/grass_path_edge_ne.png",
 "NW": "res://assets/reverie_pack_v01/Royal_Gardens/Terrain/grass_path_edge_nw.png",
 "SE": "res://assets/reverie_pack_v01/Royal_Gardens/Terrain/grass_path_edge_se.png",
 "SW": "res://assets/reverie_pack_v01/Royal_Gardens/Terrain/grass_path_edge_sw.png"
}

func _initialize() -> void:
 var packed := load(EDGE_SCENE) as PackedScene
 assert(packed != null, "New road-edge scene must load")
 var scene := packed.instantiate()
 var legacy := scene.get_node("LegacyAtlasEdges") as TileMapLayer
 var edges := scene.get_node("NewAssetRoadEdges") as Node2D
 assert(not legacy.visible, "Legacy atlas road edges must remain hidden")
 assert(edges.get_child_count() == 45, "Expected 45 new road-edge sprites, found %d" % edges.get_child_count())
 var counts := {"NE": 0, "NW": 0, "SE": 0, "SW": 0}
 for child in edges.get_children():
  assert(child is Sprite2D, "Every new edge module must be a Sprite2D")
  var sprite := child as Sprite2D
  assert(sprite.texture != null, "%s has no texture" % sprite.name)
  var direction := sprite.name.get_slice("_", 2)
  assert(EXPECTED.has(direction), "%s has an unknown edge direction" % sprite.name)
  assert(sprite.texture.resource_path == EXPECTED[direction], "%s uses the wrong new edge asset" % sprite.name)
  assert(sprite.texture.get_width() == 64 and sprite.texture.get_height() == 32, "%s must preserve 64x32 tile dimensions" % sprite.name)
  counts[direction] += 1
 assert(counts.NE > 0 and counts.NW > 0 and counts.SE > 0 and counts.SW > 0, "All four edge orientations must be represented")
 print("NEW ROAD EDGE ASSETS: PASS (45 placed sprites; NE %d, NW %d, SE %d, SW %d)" % [counts.NE, counts.NW, counts.SE, counts.SW])
 scene.free()
 quit(0)
