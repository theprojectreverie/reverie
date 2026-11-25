extends SceneTree

const FOUNDATION: PackedScene = preload("res://scenes/world/act1_tilemap_foundation.tscn")

func _initialize() -> void:
	var world := FOUNDATION.instantiate() as Node2D
	assert(world != null, "Act I tilemap foundation instantiates")
	var terrain := world.get_node("WorldTerrain")
	var transitions := world.get_node("RegionTransitions")
	var pairs := [
		["RoyalGardens", "RoyalGardensExit", "RoyalGate", "Entry", "RoyalToGate"],
		["RoyalGate", "Exit", "WillowFields", "Entry", "GateToWillow"],
		["WillowFields", "Exit", "ElderwoodGrove", "Entry", "WillowToElderwood"],
		["ElderwoodGrove", "Exit", "ForsakenRuins", "Entry", "ElderwoodToForsaken"],
		["ForsakenRuins", "Exit", "RuinedTower", "Entry", "ForsakenToTower"]
	]
	for pair in pairs:
		var source := terrain.get_node(pair[0])
		var target := terrain.get_node(pair[2])
		var source_marker := source.get_node(pair[1]) as Marker2D
		var target_marker := target.get_node(pair[3]) as Marker2D
		var transition := transitions.get_node(pair[4]) as Marker2D
		var source_world := source_marker.global_position
		var target_world := target_marker.global_position
		assert(source_world.distance_to(target_world) < 0.01, pair[0] + " exit meets " + pair[2] + " entry")
		assert(source_world.distance_to(transition.global_position) < 0.01, pair[4] + " matches both region markers")
	print("ACT1_REGION_TRANSITION_ALIGNMENT_PASS connections=", pairs.size(), " gaps=0")
	world.free()
	quit()
