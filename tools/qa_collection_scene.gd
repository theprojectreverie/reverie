extends SceneTree
func _initialize() -> void:
 var keep := load("res://scenes/world/castle_gardens/components/reverie_royal_keep.tscn") as PackedScene
 print("KEEP_EXISTS=", ResourceLoader.exists("res://scenes/world/castle_gardens/components/reverie_royal_keep.tscn"), " KEEP_STATE_NODES=", keep.get_state().get_node_count())
 var packed := load("res://scenes/world/castle_gardens/components/reverie_royal_gardens_castle_collection.tscn") as PackedScene
 print("COLLECTION_STATE_NODES=", packed.get_state().get_node_count(), " EXT_COUNT=", packed.get_state().get_node_count())
 var node := packed.instantiate()
 print("ROOT=", node.name, " CHILDREN=", node.get_child_count())
 for i in range(packed.get_state().get_node_count()):
  print("STATE_NODE_", i, "=", packed.get_state().get_node_name(i), " PATH=", packed.get_state().get_node_path(i))
 quit()
