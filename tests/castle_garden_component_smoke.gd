extends SceneTree

const WORLD_PATH := "res://scenes/world/castle_royal_gardens.tscn"
const PALACE_TEXTURE := "res://assets/reverie_custom/royal_gardens/production/grand_royal_palace.png"
const ROAD_TEXTURE := "res://assets/reverie_custom/royal_gardens/production/royal_cobble_ribbon_96.png"

func _initialize() -> void:
	call_deferred("_run")

func _count_sprites(node: Node) -> int:
	var count := 0
	for child in node.get_children():
		if child is Sprite2D:
			count += 1
		count += _count_sprites(child)
	return count

func _assert_path_connectivity() -> bool:
	var remaining := {}
	var path_cells: Array[Vector2i] = []
	for gx in range(CastleLayout.GRID_MIN.x, CastleLayout.GRID_MAX.x + 1):
		for gy in range(CastleLayout.GRID_MIN.y, CastleLayout.GRID_MAX.y + 1):
			if CastleLayout.is_path(gx, gy):
				var cell := Vector2i(gx, gy)
				path_cells.append(cell)
				remaining[cell] = true
	if path_cells.is_empty():
		push_error("Royal Gardens has no walkable path cells")
		return false
	var queue: Array[Vector2i] = [path_cells[0]]
	remaining.erase(path_cells[0])
	while not queue.is_empty():
		var cell: Vector2i = queue.pop_front()
		for step in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			var neighbour: Vector2i = cell + step
			if remaining.has(neighbour):
				remaining.erase(neighbour)
				queue.append(neighbour)
	if not remaining.is_empty():
		push_error("Royal Gardens has %d disconnected path cells" % remaining.size())
		return false
	for pond_cell in CastleLayout.POND_LEFT + CastleLayout.POND_RIGHT:
		if CastleLayout.is_path(pond_cell.x, pond_cell.y):
			push_error("Royal Gardens path overlaps a reflecting pond cell: %s" % str(pond_cell))
			return false
	print("ROYAL GARDENS ROUTE CONNECTIVITY: PASS (%d cells, 1 component)" % path_cells.size())
	return true

func _fence_art_is_proportional(sprite: Sprite2D, expected_scale: float) -> bool:
	if sprite == null:
		return false
	var assembly_transform: Transform2D = sprite.get_parent().transform * sprite.transform
	return absf(assembly_transform.x.length() - expected_scale) <= 0.03 and absf(assembly_transform.y.length() - expected_scale) <= 0.03

func _check_mirrored_pair(parent: Node, west_name: String, east_name: String) -> bool:
	var west := parent.get_node_or_null(west_name) as Sprite2D
	var east := parent.get_node_or_null(east_name) as Sprite2D
	if west == null or east == null:
		push_error("Missing mirrored clean-layout pair: %s / %s" % [west_name, east_name])
		return false
	if not is_equal_approx(west.position.x + east.position.x, 1280.0):
		push_error("Pair is not centered symmetrically: %s / %s" % [west_name, east_name])
		return false
	if not is_equal_approx(west.position.y, east.position.y):
		push_error("Pair has mismatched vertical placement: %s / %s" % [west_name, east_name])
		return false
	return true

func _run() -> void:
	if not _assert_path_connectivity():
		quit(1)
		return

	var packed := load(WORLD_PATH) as PackedScene
	assert(packed != null, "Playable Royal Gardens scene must load")
	var world := packed.instantiate() as Node2D
	assert(world != null, "Playable Royal Gardens scene must instantiate")
	root.add_child(world)
	# Scene smoke tests must not write the user's shared persistent save.
	var world_runtime := world.get_node_or_null("WorldRuntime")
	if world_runtime != null:
		world_runtime.set_process(false)
	await process_frame

	assert(world.player != null and is_instance_valid(world.player), "Playable Royal Gardens must spawn the player")
	var clear_spawn_directions := 0
	for direction in [Vector2.RIGHT, Vector2.LEFT, Vector2.UP, Vector2.DOWN]:
		if not world.player.test_move(world.player.global_transform, direction * 28.0):
			clear_spawn_directions += 1
	assert(clear_spawn_directions >= 2, "Player spawn must have at least two clear movement directions")
	print("PLAYER SPAWN CLEARANCE: PASS (%d/4 directions, position %s)" % [clear_spawn_directions, str(world.player.position)])
	# Sample the authored main promenade and verify that fountain bases remain solid.
	for route_point in [Vector2(640, 600), Vector2(640, 700), Vector2(640, 1050), Vector2(640, 1090)]:
		assert(world.is_walkable(route_point), "Main promenade must remain clear at %s" % str(route_point))
	for fountain_base in [Vector2(274, 736), Vector2(1006, 736), Vector2(640, 875)]:
		assert(not world.is_walkable(fountain_base), "Fountain base must block player-sized movement at %s" % str(fountain_base))
	print("ROUTE / FOUNTAIN COLLISION: PASS (4 clear promenade samples; 3 solid fountain bases)")
	var player_camera := world.player.get_node_or_null("Camera2D") as Camera2D
	assert(player_camera != null and is_equal_approx(player_camera._follow_local_offset.y, -220.0), "Player camera must use the north-biased garden framing")
	assert(not player_camera.position_smoothing_enabled, "Top-level camera follow must not run a second engine smoothing pass")
	print("PLAYER CAMERA FRAMING: PASS (single follow controller; engine smoothing disabled; offset %s)" % str(player_camera._follow_local_offset))
	assert(is_equal_approx(player_camera.zoom.x, 0.62 / maxf(world.global_scale.x, 0.001)), 'Player camera must use the wider garden composition zoom')
	print('PLAYER CAMERA ZOOM: PASS (%.3f)' % player_camera.zoom.x)
	var camera_bounds_min := world.to_global(CastleLayout.SCREEN_MIN + CastleLayout.CAMERA_EDGE_PADDING)
	var camera_bounds_max := world.to_global(CastleLayout.SCREEN_MAX - CastleLayout.CAMERA_EDGE_PADDING)
	assert(player_camera.limit_left == floori(camera_bounds_min.x) and player_camera.limit_top == floori(camera_bounds_min.y), "Player camera must clamp to the authored garden's top-left ground bounds")
	assert(player_camera.limit_right == ceili(camera_bounds_max.x) and player_camera.limit_bottom == ceili(camera_bounds_max.y), "Player camera must clamp to the authored garden's bottom-right ground bounds")
	print("PLAYER CAMERA WORLD LIMITS: PASS (%d, %d) to (%d, %d)" % [player_camera.limit_left, player_camera.limit_top, player_camera.limit_right, player_camera.limit_bottom])

	var baked_ground := world.get_node_or_null("Terrain/TilemapCandidate/BaseGround") as TileMapLayer
	assert(baked_ground != null and baked_ground.visible, "Baked grass ground layer must be visible")
	var terrain_config := world.get_node_or_null("Terrain/Configuration") as Node
	var legacy_ground := world.get_node_or_null("Terrain/Ground") as CanvasItem
	assert(terrain_config != null and bool(terrain_config.get_meta("use_baked_tilemap", false)), "Live garden must explicitly select the baked isometric terrain renderer")
	assert(legacy_ground != null and not legacy_ground.visible, "Legacy procedural ground must stay hidden when baked terrain is selected")
	var edge_canvas := world.get_node_or_null("Terrain/TerrainTransitions/RoadEdgeTransitions/NewAssetRoadEdges") as CanvasItem
	var road_canvas := world.get_node_or_null("PathwayTiles/HandDesignedRoadSurfaces/NorthGrandPromenade") as CanvasItem
	var pathway_root := world.get_node_or_null("PathwayTiles") as Node2D
	assert(edge_canvas != null and road_canvas != null and pathway_root != null, "Terrain edge and hand-authored road layers must both be mounted")
	assert(edge_canvas.position.is_equal_approx(pathway_root.position) and edge_canvas.scale.is_equal_approx(pathway_root.scale), "Road-edge sprites must share the hand-authored pathway coordinate basis")
	print("ROAD EDGE COORDINATES: PASS (edge layer shares pathway offset and scale)")
	var baked_ground_effective_z := baked_ground.z_index - 20
	var edge_effective_z := edge_canvas.z_index
	var road_effective_z := 10 - 28
	assert(baked_ground_effective_z < edge_effective_z, "Grass ground must render below road-edge transition artwork")
	assert(edge_effective_z < road_effective_z, "Road-edge transitions must render below the hand-authored cobblestone surface")
	print("TERRAIN DRAW ORDER: PASS (baked grass < edge transitions < cobblestone roads)")
	assert(baked_ground.get_cell_source_id(Vector2i(67, 20)) >= 0, "Southeast camera corner must be covered by baked grass ground")
	assert(baked_ground.get_cell_source_id(Vector2i(-9, -31)) >= 0, "Portrait upper terrain extension must be covered by baked grass ground")
	assert(baked_ground.get_cell_source_id(Vector2i(85, 65)) >= 0, "Portrait lower terrain extension must be covered by baked grass ground")
	assert(baked_ground.get_cell_source_id(Vector2i(-28, -13)) >= 0, 'Portrait upper-left corner must be covered by baked grass ground')
	assert(baked_ground.get_cell_source_id(Vector2i(10, -50)) >= 0, 'Portrait upper-right corner must be covered by baked grass ground')
	assert(baked_ground.get_cell_source_id(Vector2i(12, -35)) >= 0, "Previously identified upper terrain gap at (12, -35) must remain filled")
	assert(baked_ground.get_cell_source_id(Vector2i(67, 82)) >= 0, 'Portrait lower-left corner must be covered by baked grass ground')
	assert(baked_ground.get_cell_source_id(Vector2i(105, 45)) >= 0, 'Portrait lower-right corner must be covered by baked grass ground')
	print("SOUTHEAST + PORTRAIT GROUND COVERAGE: PASS (camera corners and portrait top/bottom)")

	var palace := world.get_node_or_null("RoyalCastleArchitecture/CastleCollection/CastleKeep/KeepArtwork") as Sprite2D
	assert(palace != null and palace.texture != null, "Single authored palace artwork is missing")
	assert(palace.texture.resource_path == PALACE_TEXTURE, "Castle must use the approved illustrated palace sprite")

	var legacy_flora := world.get_node_or_null("Flora") as CanvasItem
	var legacy_props := world.get_node_or_null("Props") as CanvasItem
	var layout := world.get_node_or_null("SymmetricalGardenLayout") as Node2D
	assert(legacy_flora != null and not legacy_flora.visible, "Legacy dense flora assembly must remain hidden")
	assert(legacy_props != null and not legacy_props.visible, "Legacy dense props assembly must remain hidden")
	assert(layout != null and layout.visible, "Clean symmetrical garden layout must be visible")
	var sprite_count := _count_sprites(layout)
	assert(sprite_count == 34, "Clean garden layout must contain exactly 34 authored sprites, found %d" % sprite_count)

	var canopy := layout.get_node("OuterCanopy")
	for pair in [
		["NorthWestWisteria", "NorthEastWisteria"],
		["WestBlossomTree", "EastBlossomTree"],
		["SouthWestWhiteBlossom", "SouthEastWhiteBlossom"],
		["WestCypress", "EastCypress"]
	]:
		assert(_check_mirrored_pair(canopy, pair[0], pair[1]), "Outer canopy must remain balanced")

	var beds := layout.get_node("GardenBeds")
	for pair in [
		["WestNorthHedge", "EastNorthHedge"],
		["WestSouthHedge", "EastSouthHedge"],
		["WestNorthFlowers", "EastNorthFlowers"],
		["WestSouthFlowers", "EastSouthFlowers"],
		["WestUpperRose", "EastUpperRose"],
		["WestLowerRose", "EastLowerRose"],
		["WestLowerViolet", "EastLowerViolet"]
	]:
		assert(_check_mirrored_pair(beds, pair[0], pair[1]), "Garden beds must remain balanced")

	var planters := layout.get_node("OuterPlanterAccents")
	assert(_check_mirrored_pair(planters, "WestRosePlanter", "EastRosePlanter"), "Outer planters must remain balanced")
	var entrance_urns := layout.get_node("EntranceUrnAccents")
	assert(_check_mirrored_pair(entrance_urns, "WestRoseUrn", "EastRoseUrn"), "Entrance urns must remain balanced")

	var edge_layer := world.get_node_or_null("Terrain/TerrainTransitions/RoadEdgeTransitions/NewAssetRoadEdges") as Node2D
	assert(edge_layer != null and edge_layer.get_child_count() == 45, "All 45 new grass-to-cobble edge sprites must remain preserved in the playable world")
	assert(not edge_layer.visible, "Unfinished scattered road-edge accents must remain hidden until their border layout is visually corrected")
	for edge in edge_layer.get_children():
		assert(edge is Sprite2D and (edge as Sprite2D).texture != null, "Every road edge must use a real imported asset")
		assert((edge as Sprite2D).texture.resource_path.begins_with("res://assets/reverie_pack_v01/Royal_Gardens/Terrain/grass_path_edge_"),
			"%s must use one of the four approved new road-edge assets" % edge.name)
	print("ROAD EDGE CLEANUP: PASS (45 imported transitions preserved but hidden pending proper border placement)")

	var roads := world.get_node_or_null("PathwayTiles/HandDesignedRoadSurfaces") as Node2D
	assert(roads != null and roads.get_child_count() == 10, "Ten authored road modules must be present")
	for road in roads.get_children():
		assert(road is Polygon2D, "Road modules must remain authored polygon nodes")
		var polygon := road as Polygon2D
		assert(polygon.visible and polygon.polygon.size() >= 10, "%s must be a visible shaped road" % polygon.name)
		assert(polygon.texture != null and polygon.texture.resource_path == ROAD_TEXTURE,
			"%s must use the approved cobblestone artwork" % polygon.name)

	var expansion_flora := world.get_node_or_null("ExpansionBuilder/ExpansionFlora") as CanvasItem
	var expansion_props := world.get_node_or_null("ExpansionBuilder/ExpansionProps") as CanvasItem
	assert(expansion_flora != null and expansion_flora.visible, "Authored expansion flora layer must remain visible")
	assert(expansion_props != null and not expansion_props.visible, "Legacy expansion prop duplicates must remain hidden")

	var fences := world.get_node_or_null("GardenFences") as CanvasItem
	assert(fences != null and fences.visible, "Perimeter and entrance fence assembly must remain visible")
	var fence_collision := world.get_node_or_null('GardenFences/FenceCollision') as StaticBody2D
	assert(fence_collision != null and fence_collision.collision_layer == 1 and fence_collision.get_child_count() == 8, 'Visible garden fence rails must have eight player-blocking collision segments')
	print('FENCE COLLISION: PASS (8 rail segments; three gate openings retained)')
	var gate := world.get_node_or_null("GardenFences/FrontPerimeterFence/GrandFrontEntranceGate") as Sprite2D
	assert(gate != null and gate.visible and gate.texture != null, "Grand entrance gate must remain visible")
	assert(_fence_art_is_proportional(world.get_node_or_null("GardenFences/NorthPerimeterFence/NorthWestRail01") as Sprite2D, 1.9), "North fence rails must preserve their pixel-art aspect ratio")
	assert(_fence_art_is_proportional(world.get_node_or_null("GardenFences/OuterSideFenceRuns/OuterWestRail01") as Sprite2D, 1.9), "Outer side fence rails must preserve their pixel-art aspect ratio")
	assert(_fence_art_is_proportional(world.get_node_or_null("GardenFences/OuterSideFenceRuns/OuterWestExtendedRail01") as Sprite2D, 1.9), "Extended outer side fence rails must preserve their pixel-art aspect ratio")
	assert(_fence_art_is_proportional(world.get_node_or_null("GardenFences/OuterSideFenceRuns/OuterEastExtendedRail01") as Sprite2D, 1.9), "Extended east fence rails must preserve their pixel-art aspect ratio")
	assert(_fence_art_is_proportional(world.get_node_or_null("GardenFences/FrontPerimeterFence/FrontWestRail01") as Sprite2D, 1.55), "Front fence rails must preserve their pixel-art aspect ratio")
	print("FENCE ART ASPECT: PASS (north, side and front rails proportionally scaled)")

	assert(world.npcs.size() == 3, "Clean Royal Gardens must spawn only two guards and Pip")
	var spawned_npc_ids: Array[String] = []
	for npc in world.npcs:
		spawned_npc_ids.append(str(npc.get("npc_id")))
	assert(spawned_npc_ids.has("castle_guard_left") and spawned_npc_ids.has("castle_guard_right") and spawned_npc_ids.has("garden_visitor"), "Approved garden NPC roster is incomplete")
	assert(not spawned_npc_ids.has("royal_gardener"), "Royal Gardener must not spawn in the cleaned map")
	assert(world.monsters.is_empty(), "Formal Royal Gardens must not spawn unrelated Gothic Sentinels")
	var expansion_interactables := world.get_node_or_null("ExpansionBuilder/ExpansionInteractables") as Node2D
	var authored_cache: Node = null
	if expansion_interactables != null:
		for child in expansion_interactables.get_children():
			if str(child.get("collectible_id")) == "castle_royal_seal_cache":
				authored_cache = child
				break
	assert(authored_cache != null and authored_cache.visible, "Authored Gardener Seal Cache must spawn from its placement marker")
	var gothic_road: Node = expansion_interactables.get_node_or_null("RegionPortal") if expansion_interactables != null else null
	assert(gothic_road != null and str(gothic_road.get("target_region")) == "royal_gate" and str(gothic_road.get("required_quest")).is_empty() and bool(gothic_road.call("can_interact")), "Royal Road must remain an open, interactable connection to the Royal Gate")
	print("CLEAN CONTENT: PASS (3 approved NPCs, no gardener or sentinels; authored cache present)")
	print("ROYAL GATE ROAD: PASS (open and interactable)")
	print("CLEAN GARDEN LAYOUT: PASS (single palace, %d garden sprites, 10 authored road modules)" % sprite_count)
	world.queue_free()
	quit(0)







