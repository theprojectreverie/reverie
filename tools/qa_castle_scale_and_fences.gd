extends SceneTree

func _initialize() -> void:
 var playable := load("res://scenes/world/castle_royal_gardens.tscn") as PackedScene
 if playable == null:
  push_error("PLAYABLE_GARDEN_SCENE_LOAD_FAILED")
  quit(1)
  return
 var world := playable.instantiate()
 root.add_child(world)
 await process_frame
 var fences := world.get_node_or_null("GardenFences/FenceRuns") as Node2D
 var side_gates := world.get_node_or_null("GardenFences/FrontPerimeterFence/SideGateArchways")
 var live_castle := world.get_node_or_null("RoyalCastleArchitecture") as Node2D
 var collection := world.get_node_or_null("RoyalCastleArchitecture/CastleCollection") as Node2D
 if fences == null or side_gates == null or live_castle == null or collection == null:
  push_error("PLAYABLE_FENCE_OR_CASTLE_ASSEMBLY_MISSING")
  quit(1)
  return
 var keep := collection.get_node_or_null("CastleKeep") as Node2D
 if keep == null or collection.get_child_count() != 1:
  push_error("CASTLE_MUST_BE_ONE_PALACE_ONLY child_count=%d" % collection.get_child_count())
  quit(1)
  return
 if not live_castle.global_position.is_equal_approx(Vector2(-416.0, -196.0)) or not live_castle.global_scale.is_equal_approx(Vector2(1.65, 1.65)):
  push_error("PLAYABLE_CASTLE_TRANSFORM_MISMATCH pos=%s scale=%s" % [str(live_castle.global_position), str(live_castle.global_scale)])
  quit(1)
  return
 if fences.get_child_count() < 24 or side_gates.get_child_count() != 2 or keep.scale.x < 1.17:
  push_error("CASTLE_FENCE_LAYOUT_ASSERTION_FAILED")
  quit(1)
  return
 print("PLAYABLE_FENCE_SPRITES=", fences.get_child_count())
 print("CASTLE_COLLECTION_CHILDREN=", collection.get_child_count(), " KEEP_SCALE=", keep.scale)
 print("PLAYABLE_CASTLE_GLOBAL_POSITION=", live_castle.global_position, " SCALE=", live_castle.global_scale)
 print("CASTLE_SINGLE_PALACE_AND_FENCE_QA_OK")
 quit()
