extends SceneTree

const FOUNDATION := preload("res://scenes/world/act1_tilemap_foundation.tscn")
const WORLD_STRUCTURE := preload("res://scenes/world/act1_world_structure.tscn")
const REGION_NAMES := ["RoyalGardens", "RoyalGate", "WillowFields", "ElderwoodGrove", "ForsakenRuins", "RuinedTower"]
const LAYER_NAMES := ["GroundBlend", "Paths", "Water", "Vegetation", "Foreground"]

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var foundation := FOUNDATION.instantiate()
	root.add_child(foundation)
	var world := foundation.get_node_or_null("WorldTerrain")
	assert(world != null, "WorldTerrain root exists")

	for region_name in REGION_NAMES:
		var region := world.get_node_or_null(region_name)
		assert(region != null, "%s region exists" % region_name)
		var candidate := region.get_node_or_null("GeneratedGrassCandidate") as TileMapLayer
		assert(candidate != null, "%s generated grass candidate exists" % region_name)
		assert(candidate.tile_set != null, "%s generated grass TileSet assigned" % region_name)
		assert(candidate.tile_set.tile_size == Vector2i(64, 32), "%s candidate uses isometric logical grid" % region_name)
		assert(not candidate.visible, "%s candidate remains hidden pending tile refinement" % region_name)
		for layer_name in LAYER_NAMES:
			var layer := region.get_node_or_null(layer_name) as TileMapLayer
			assert(layer != null, "%s/%s exists" % [region_name, layer_name])
			assert(layer.tile_set != null, "%s/%s TileSet assigned" % [region_name, layer_name])
		assert(region.get_node_or_null("CollisionGeometry") != null, "%s collision authoring group exists" % region_name)
		assert(region.get_node_or_null("Entry") != null or region.get_node_or_null("RoyalGardensEntry") != null, "%s entry marker exists" % region_name)
		assert(region.get_node_or_null("Exit") != null or region.get_node_or_null("RoyalGardensExit") != null, "%s exit marker exists" % region_name)
		if region_name != "RoyalGardens":
			var active_ground := region.get_node_or_null("BaseGround") as TileMapLayer
			assert(active_ground != null, "%s active ground layer exists" % region_name)
			assert(active_ground.tile_set.tile_size == Vector2i(64, 32), "%s active ground is isometric" % region_name)

	var baked := world.get_node_or_null("RoyalGardens/BakedRoyalGardenTerrain")
	assert(baked != null, "Existing baked Royal Gardens tilemap is mounted")
	assert(baked.get_node_or_null("BaseGround") != null, "Royal Gardens keeps its authored baked ground")
	assert(foundation.get_node_or_null("RegionTransitions") != null, "Five transition markers exist")

	var gate_arch := world.get_node_or_null("RoyalGate/RoyalGateArchitecture")
	assert(gate_arch != null, "Royal Gate modular architecture is mounted")
	for node_name in ["Architecture/MainGate", "Architecture/LeftWall", "Architecture/RightWall", "Architecture/LeftTower", "Architecture/RightTower", "ApproachLanterns/LeftLantern", "ApproachLanterns/RightLantern", "CourtyardDetails/LeftGuardian", "CourtyardDetails/RightGuardian", "CourtyardDetails/LeftWisteria", "CourtyardDetails/RightWisteria", "CourtyardDetails/SideFountain", "CourtyardDetails/GardenBench", "CourtyardDetails/LeftVioletShrub", "CourtyardDetails/RightVioletShrub", "ApproachPath", "GateThreshold", "ArrivalPoint"]:
		assert(gate_arch.get_node_or_null(node_name) != null, "Royal Gate component %s exists" % node_name)
	assert(gate_arch.get_node("ApproachPath") is TileMapLayer, "Royal Gate path remains an editable TileMapLayer")
	var approach_path := gate_arch.get_node("ApproachPath") as TileMapLayer
	assert(approach_path.tile_set != null, "Royal Gate approach has its path TileSet assigned")
	assert(approach_path.tile_set.tile_size == Vector2i(64, 32), "Royal Gate approach uses the established isometric logical grid")
	assert(approach_path.tile_set.tile_shape == 1 and approach_path.tile_set.tile_layout == 5, "Royal Gate approach uses isometric diamond layout")
	var path_atlas := approach_path.tile_set.get_source(0) as TileSetAtlasSource
	assert(path_atlas != null, "Royal Gate approach atlas source 0 exists")
	assert(path_atlas.texture.get_size() == Vector2(128, 128), "Royal Gate path atlas remains a 128x128 source image")
	assert(path_atlas.texture_region_size == Vector2i(32, 32), "Royal Gate path atlas retains 32x32 art regions")
	assert(path_atlas.get_tiles_count() == 16, "Royal Gate path atlas exposes all sixteen authored regions")
	assert(approach_path.get_used_cells().is_empty(), "Royal Gate approach remains unpainted for manual editor authoring")
	var gate_ground := world.get_node("RoyalGate/BaseGround") as TileMapLayer
	var ground_atlas := gate_ground.tile_set.get_source(0) as TileSetAtlasSource
	assert(ground_atlas != null, "Royal Gate ground atlas source 0 exists")
	assert(ground_atlas.texture.get_size() == Vector2(128, 128), "Royal Gate ground atlas remains a 128x128 source image")
	assert(ground_atlas.texture_region_size == Vector2i(32, 32), "Royal Gate ground atlas retains 32x32 art regions")
	assert(ground_atlas.get_tiles_count() == 16, "Royal Gate ground atlas exposes all sixteen authored regions")
	var collision_root := gate_arch.get_node("CollisionGeometry")
	var blocker_names := ["LeftWallBlocker", "LeftGatePierBlocker", "RightGatePierBlocker", "RightWallBlocker"]
	for blocker_name in blocker_names:
		var blocker := collision_root.get_node_or_null(blocker_name) as StaticBody2D
		assert(blocker != null, "Royal Gate blocker %s exists" % blocker_name)
		assert(blocker.collision_layer == 1, "Royal Gate blocker %s is on world collision layer" % blocker_name)
		var shape := blocker.get_node_or_null("Shape") as CollisionShape2D
		assert(shape != null and shape.shape is RectangleShape2D, "Royal Gate blocker %s has a rectangle collider" % blocker_name)
	assert(collision_root.get_child_count() == 12, "Four wall blockers and eight prop blockers are mounted")
	for prop_blocker_name in ["LeftGuardianBlocker", "RightGuardianBlocker", "LeftWisteriaBlocker", "RightWisteriaBlocker", "SideFountainBlocker", "GardenBenchBlocker", "LeftVioletShrubBlocker", "RightVioletShrubBlocker"]:
		var prop_blocker := collision_root.get_node_or_null(prop_blocker_name) as StaticBody2D
		assert(prop_blocker != null and prop_blocker.collision_layer == 1, "Forecourt prop %s has world collision" % prop_blocker_name)
	assert(gate_arch.get_node("GateThreshold").position.x == 0.0, "Gate threshold stays centered on the opening")

	var world_structure := WORLD_STRUCTURE.instantiate()
	root.add_child(world_structure)
	var master_gate := world_structure.get_node_or_null("LandmarkNodes/RoyalGate")
	assert(master_gate != null, "Act I world composition mounts the modular Royal Gate scene")
	assert(master_gate.get_node_or_null("CourtyardDetails/SideFountain") != null, "Act I world composition includes the authored forecourt")
	assert(master_gate.get_node_or_null("CollisionGeometry/SideFountainBlocker") != null, "Act I world composition includes prop collision")
	print("ACT1_TILEMAP_FOUNDATION_PASS regions=6 layers_per_region=6 isometric_grid=64x32 royal_gate_modular_art=true forecourt_props=8 wall_blockers=4 prop_blockers=8 generated_grass_candidate_hidden=true")
	quit(0)
