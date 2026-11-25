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

func _check_pair(parent: Node, west_name: String, east_name: String, center_x: float) -> bool:
	var west := parent.get_node_or_null(west_name) as Sprite2D
	var east := parent.get_node_or_null(east_name) as Sprite2D
	if west == null or east == null:
		push_error("Missing clean-layout mirror pair: %s / %s" % [west_name, east_name])
		return false
	if not is_equal_approx(west.position.x + east.position.x, center_x):
		push_error("Pair is not mirrored around the garden center: %s / %s" % [west_name, east_name])
		return false
	if not is_equal_approx(west.position.y, east.position.y):
		push_error("Pair has mismatched vertical placement: %s / %s" % [west_name, east_name])
		return false
	return true

func _run() -> void:
	var packed := load(WORLD_PATH) as PackedScene
	assert(packed != null, "Playable Royal Gardens scene must load")
	var world := packed.instantiate() as Node2D
	assert(world != null, "Playable Royal Gardens scene must instantiate")
	root.add_child(world)
	await process_frame

	var palace := world.get_node_or_null("RoyalCastleArchitecture/CastleCollection/CastleKeep/KeepArtwork") as Sprite2D
	assert(palace != null and palace.texture != null, "Single authored palace artwork is missing")
	assert(palace.texture.resource_path == PALACE_TEXTURE, "Castle must use the approved illustrated palace sprite")

	var baked_terrain := world.get_node_or_null("Terrain/TilemapCandidate") as Node2D
	var generated_ground := world.get_node_or_null("Terrain/Ground") as CanvasItem
	var generated_details := world.get_node_or_null("Terrain/GrassDetails") as CanvasItem
	assert(baked_terrain != null and baked_terrain.visible, "Royal Gardens uses the authored baked TileMapLayer assembly")
	assert(baked_terrain.get_node_or_null("BaseGround") is TileMapLayer, "Base terrain is a serialized TileMapLayer")
	assert(baked_terrain.get_node_or_null("Paths") is TileMapLayer, "Paths are serialized TileMapLayer nodes")
	assert(generated_ground != null and not generated_ground.visible, "Runtime polygon ground fallback stays disabled")
	assert(generated_details != null and not generated_details.visible, "Runtime polygon grass details stay disabled")

	var legacy_flora := world.get_node_or_null("Flora") as CanvasItem
	var legacy_props := world.get_node_or_null("Props") as CanvasItem
	var clean_layout := world.get_node_or_null("SymmetricalGardenLayout") as Node2D
	assert(legacy_flora != null and not legacy_flora.visible, "Legacy dense flora assembly must remain hidden")
	assert(legacy_props != null and not legacy_props.visible, "Legacy dense props assembly must remain hidden")
	assert(clean_layout != null and clean_layout.visible, "Clean symmetrical garden layout must be visible")

	var expected_sprites := 34
	var sprite_count := _count_sprites(clean_layout)
	assert(sprite_count == expected_sprites, "Clean garden layout expected %d authored sprites, found %d" % [expected_sprites, sprite_count])

	var canopy := clean_layout.get_node("OuterCanopy")
	for pair in [
		["NorthWestWisteria", "NorthEastWisteria"],
		["WestBlossomTree", "EastBlossomTree"],
		["SouthWestWhiteBlossom", "SouthEastWhiteBlossom"],
		["WestCypress", "EastCypress"]
	]:
		assert(_check_pair(canopy, pair[0], pair[1], 1280.0), "Outer canopy must remain balanced")

	var beds := clean_layout.get_node("GardenBeds")
	for pair in [
		["WestNorthHedge", "EastNorthHedge"],
		["WestSouthHedge", "EastSouthHedge"],
		["WestNorthFlowers", "EastNorthFlowers"],
		["WestSouthFlowers", "EastSouthFlowers"],
		["WestUpperRose", "EastUpperRose"],
		["WestLowerRose", "EastLowerRose"],
		["WestLowerViolet", "EastLowerViolet"]
	]:
		assert(_check_pair(beds, pair[0], pair[1], 1280.0), "Garden beds must remain balanced")

	var planters := clean_layout.get_node("OuterPlanterAccents")
	assert(_check_pair(planters, "WestRosePlanter", "EastRosePlanter", 1280.0), "Outer planters must remain balanced")
	var urns := clean_layout.get_node("EntranceUrnAccents")
	assert(_check_pair(urns, "WestRoseUrn", "EastRoseUrn", 1280.0), "Entrance urns must remain balanced")

	var roads := world.get_node_or_null("PathwayTiles/HandDesignedRoadSurfaces") as Node2D
	assert(roads != null, "Hand-authored cobblestone road assembly is missing")
	assert(roads.get_child_count() == 10, "Expected ten authored road ribbons")
	for road in roads.get_children():
		assert(road is Polygon2D, "Road modules must remain authored polygon nodes")
		var polygon := road as Polygon2D
		assert(polygon.visible and polygon.polygon.size() >= 10, "%s must be a visible shaped road" % polygon.name)
		assert(polygon.texture != null and polygon.texture.resource_path == ROAD_TEXTURE,
			"%s must use the approved cobblestone artwork" % polygon.name)

	var fences := world.get_node_or_null("GardenFences") as CanvasItem
	assert(fences != null and fences.visible, "Perimeter and entrance fence assembly must remain visible")
	print("CLEAN GARDEN LAYOUT: PASS (single palace, %d garden sprites, 10 authored road modules)" % sprite_count)
	world.queue_free()
	quit(0)
