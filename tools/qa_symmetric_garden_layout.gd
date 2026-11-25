extends SceneTree

func _initialize() -> void:
 var packed := load("res://scenes/world/castle_royal_gardens.tscn") as PackedScene
 if packed == null:
  push_error("SYMMETRIC_GARDEN_SCENE_MISSING")
  quit(1)
  return
 var world := packed.instantiate()
 root.add_child(world)
 await process_frame
 var layout := world.get_node_or_null("SymmetricalGardenLayout") as Node2D
 var flora := world.get_node_or_null("Flora") as Node2D
 var props := world.get_node_or_null("Props") as Node2D
 var expansion_flora := world.get_node_or_null("ExpansionBuilder/ExpansionFlora") as Node2D
 var expansion_props := world.get_node_or_null("ExpansionBuilder/ExpansionProps") as Node2D
 var expansion_interactables := world.get_node_or_null("ExpansionBuilder/ExpansionInteractables") as Node2D
 var castle_collection := world.get_node_or_null("RoyalCastleArchitecture/CastleCollection") as Node2D
 var roads := world.get_node_or_null("PathwayTiles/HandDesignedRoadSurfaces") as Node2D
 var outer_fences := world.get_node_or_null("GardenFences/OuterSideFenceRuns") as Node2D
 var north_fences := world.get_node_or_null("GardenFences/NorthPerimeterFence") as Node2D
 var fence_collision := world.get_node_or_null("GardenFences/FenceCollision") as StaticBody2D
 if layout == null or flora == null or props == null or expansion_flora == null or expansion_props == null or expansion_interactables == null or castle_collection == null or roads == null or outer_fences == null or north_fences == null or fence_collision == null:
  push_error("SYMMETRIC_GARDEN_REQUIRED_LAYER_MISSING")
  quit(1)
  return
 if not layout.visible or flora.visible or props.visible:
  push_error("SYMMETRIC_GARDEN_LAYER_VISIBILITY_INVALID")
  quit(1)
  return
 if expansion_flora.visible or expansion_props.visible or not expansion_interactables.visible:
  push_error("EXPANSION_DECORATION_OR_INTERACTABLE_VISIBILITY_INVALID")
  quit(1)
  return
 if outer_fences.visible or north_fences.visible or fence_collision.get_child_count() != 8:
  push_error("PERIMETER_DECORATION_OR_COLLISION_INVALID outer=%s north=%s rails=%d" % [str(outer_fences.visible), str(north_fences.visible), fence_collision.get_child_count()])
  quit(1)
  return
 if castle_collection.get_child_count() != 1 or roads.get_child_count() != 10:
  push_error("SYMMETRIC_GARDEN_CASTLE_OR_ROAD_STRUCTURE_INVALID")
  quit(1)
  return
 var placements := world.get_node("ExpansionBuilder/ApproachPlacements")
 var active_assets := 0
 for marker in placements.get_children():
  if marker is Marker2D and str(marker.get_meta("placement_type", "asset")) == "asset":
   active_assets += 1
 if active_assets != 21 or expansion_flora.get_child_count() != 15 or expansion_props.get_child_count() < 6:
  push_error("AUTHORED_EXPANSION_DECORATION_COUNTS_INVALID markers=%d flora=%d props=%d" % [active_assets, expansion_flora.get_child_count(), expansion_props.get_child_count()])
  quit(1)
  return
 var expected_pairs := [
  ["OuterCanopy/WestBlossomTree", "OuterCanopy/EastBlossomTree"],
  ["OuterCanopy/NorthWestWisteria", "OuterCanopy/NorthEastWisteria"],
  ["OuterCanopy/SouthWestWhiteBlossom", "OuterCanopy/SouthEastWhiteBlossom"],
  ["GardenBeds/WestNorthHedge", "GardenBeds/EastNorthHedge"],
  ["GardenBeds/WestSouthHedge", "GardenBeds/EastSouthHedge"],
  ["Furnishings/WestGuardian", "Furnishings/EastGuardian"],
  ["Furnishings/WestBench", "Furnishings/EastBench"]
 ]
 for pair in expected_pairs:
  var west := layout.get_node(pair[0]) as Node2D
  var east := layout.get_node(pair[1]) as Node2D
  if not is_equal_approx(west.position.x + east.position.x, 1280.0) or not is_equal_approx(west.position.y, east.position.y):
   push_error("ASYMMETRIC_PAIR=%s / %s" % [pair[0], pair[1]])
   quit(1)
   return
 var portal := expansion_interactables.get_node_or_null("RegionPortal")
 var portal_count := 0
 for child in expansion_interactables.get_children():
  if child.name == "RegionPortal":
   portal_count += 1
 var portal_ready: bool = false
 if portal != null and portal.has_method("can_interact"):
  portal_ready = portal.is_visible_in_tree() and bool(portal.call("can_interact"))
 if portal_count != 1 or portal == null or not portal_ready or expansion_interactables.get_child_count() != 1:
  push_error("PORTAL_NOT_VISIBLE_AND_INTERACTABLE portal_count=%d portal=%s" % [portal_count, str(portal)])
  quit(1)
  return
 print("SYMMETRIC_PAIRS_OK=", expected_pairs.size())
 print("REDUNDANT_EXPANSION_ASSETS=", active_assets)
 print("PORTAL_ONLY_INTERACTABLE_LAYER=true")
 print("DECORATIVE_OUTER_FENCES_HIDDEN=true COLLISION_RAILS=", fence_collision.get_child_count())
 print("PALACE_ONLY=true ROADS=", roads.get_child_count())
 print("SYMMETRIC_GARDEN_LAYOUT_OK")
 quit()
