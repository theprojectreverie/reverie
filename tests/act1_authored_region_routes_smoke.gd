extends SceneTree

const FOUNDATION: PackedScene = preload("res://scenes/world/act1_tilemap_foundation.tscn")

func _initialize() -> void:
	var world := FOUNDATION.instantiate() as Node2D
	assert(world != null, "Act I tilemap foundation instantiates")
	var terrain := world.get_node("WorldTerrain")
	var region_names := ["RoyalGate", "WillowFields", "ElderwoodGrove", "ForsakenRuins", "RuinedTower"]
	var expected_points := [7, 8, 9, 9, 8]
	for i in range(region_names.size()):
		var region := terrain.get_node(region_names[i])
		var route := region.get_node_or_null("AuthoredRoute") as Node2D
		assert(route != null, region_names[i] + " authored route group exists")
		var bed := route.get_node_or_null("RouteBed") as Line2D
		var stone := route.get_node_or_null("RouteStone") as Line2D
		assert(bed != null and stone != null, region_names[i] + " has route bed and stone surface")
		assert(bed.points.size() == expected_points[i], region_names[i] + " route control points are authored")
		assert(stone.points.size() == bed.points.size(), region_names[i] + " stone surface follows route bed")
		assert(bed.width > stone.width, region_names[i] + " route bed frames the walkable visual")
		var entry := region.get_node("Entry") as Marker2D
		var exit := region.get_node("Exit") as Marker2D
		assert(bed.points[0].distance_to(entry.position) < 0.01, region_names[i] + " route begins at entry")
		assert(bed.points[bed.points.size() - 1].distance_to(exit.position) < 0.01, region_names[i] + " route ends at exit")
		assert(bed.z_index == 0 and route.z_index == -28, region_names[i] + " route renders in path layer band")
	print("ACT1_AUTHORED_REGION_ROUTES_PASS regions=5 layered_routes=10 endpoints=10")
	world.free()
	quit()
