extends Node

const WORLD_SCENE: PackedScene = preload("res://scenes/world/greenward_world.tscn")
const LANDMARKS := {
	"royal_gate": ["royal_gate_landmark", "royal_gate_landmark"],
	"willow_fields": ["willow_fields_landmark", "willow_fields_windmill"],
	"elderwood_grove": ["elderwood_grove_landmark", "ancient_watch"],
	"forsaken_ruins": ["forsaken_ruins_landmark", "forsaken_arch"],
	"ruined_tower": ["ruined_tower_landmark", "ruined_tower_landmark"],
}
func _ready() -> void:
	_run()

func _run() -> void:
	var greenward := WORLD_SCENE.instantiate() as GreenwardWorld
	greenward.region_id = GreenwardWorld.DEFAULT_REGION_ID
	add_child(greenward)
	await get_tree().process_frame
	await get_tree().process_frame
	var authored_village := greenward.get_node_or_null("Village") as VillageEnvironment
	assert(authored_village != null and authored_village.visible, "Greenward village gameplay scene remains present")
	for layer_name in ["Ground", "TerrainTransitions", "PathNetwork", "WaterAndBridges", "Lighting", "AmbientEffects", "EnvironmentPresentation"]:
		var layer := authored_village.get_node_or_null(layer_name) as CanvasItem
		assert(layer != null and not layer.visible, "Code-drawn village environment layer is hidden: " + layer_name)
	assert(authored_village.get_district_ids().size() == 6, "Hidden village paths retain their six navigation districts")
	var preserved_edgar := greenward.entities.get_node_or_null("Edgar") as Node2D
	assert(preserved_edgar != null and preserved_edgar.visible, "Authored village NPC remains visible")
	var hidden_placeholder_count := 0
	var generated_tree_count := 0
	var authored_tree_count := 0
	for child in greenward.entities.get_children():
		var building := child.get_node_or_null("Building")
		if child is ForestTree:
			generated_tree_count += 1
			var tree := child as ForestTree
			assert(tree.visible, "Authored environment tree is visible: " + tree.name)
			assert(tree.canopy_sprite.texture != null, "Tree uses a loaded authored illustration: " + tree.prop_kind)
			assert(tree._is_authored_environment_kind(tree.prop_kind), "Tree kind resolves to dedicated authored environment art: " + tree.prop_kind)
			assert(tree.occlusion_area != null and tree.occlusion_area.get_node_or_null("CollisionShape2D") != null, "Tree canopy occlusion sensor remains present")
			assert(tree.anim != null and tree.anim.has_animation("canopy_fade") and tree.anim.has_animation("canopy_restore"), "Tree canopy fade and restore animations remain")
			authored_tree_count += 1
		elif child is VillageProp or building is VillageBuildingComponent:
			hidden_placeholder_count += 1
			assert(not (child as CanvasItem).visible, "Unreplaced procedural placeholder prop/building art is hidden: " + child.name)
	assert(hidden_placeholder_count > 0, "Unreplaced village placeholder props/buildings remain safely retired")
	assert(generated_tree_count == 18 and authored_tree_count == generated_tree_count, "All 18 authored tree placements are restored with dedicated illustrations")
	var hidden_building_shape := greenward.entities.get_node_or_null("HomeNW/Building/Collision/StaticBody2D/CollisionShape") as CollisionShape2D
	assert(hidden_building_shape != null and hidden_building_shape.disabled, "Hidden placeholder buildings no longer block movement invisibly")
	assert(greenward.npcs.size() == greenward.greenward_builder_component.composition_data.village_npcs.size(), "Greenward village NPC definitions still spawn")
	assert(greenward._portals.size() == greenward.region.get("connections", []).size(), "Greenward gameplay portals remain")
	for portal in greenward._portals:
		assert(portal is RegionPortal, "Region transition remains a real interactable portal")
		var portal_art := portal.get_node_or_null("PortalArtwork") as Sprite2D
		assert(portal_art != null and portal_art.texture != null, "Portal uses its authored SVG scene artwork")
		assert(portal.get_node_or_null("PortalBase") == null and portal.get_node_or_null("PortalRing") == null and portal.get_node_or_null("PortalInnerRing") == null, "Retired code-composed portal geometry is absent")
		assert(portal.get_node_or_null("Label") is Label and (portal.get_node("Label") as Label).visible, "Readable destination label remains")
		assert(portal.get_node_or_null("Sprite2D") == null and portal.get_node_or_null("PointLight2D") == null, "Retired generated waypoint sprite and glow are absent")
	var travel_events: Array = []
	var first_portal := greenward._portals[0] as RegionPortal
	var travel_listener := func(target_region: String, entry_point: String) -> void:
		travel_events.append([target_region, entry_point])
	EventBus.region_change_requested.connect(travel_listener)
	first_portal.interact()
	assert(travel_events.size() == 1, "Portal interaction still requests a region transition")
	assert(travel_events[0][0] == first_portal.target_region and travel_events[0][1] == first_portal.entry_point, "Portal request preserves destination and entry point")
	EventBus.region_change_requested.disconnect(travel_listener)
	var found_retired_noise_water := false
	var noise_water_grid := Vector2.ZERO
	for gx in range(-80, 81):
		for gy in range(-80, 81):
			if greenward.elevation.get_noise_2d(float(gx), float(gy)) < greenward.get_water_level():
				noise_water_grid = Vector2(gx, gy)
				found_retired_noise_water = true
				break
		if found_retired_noise_water:
			break
	assert(found_retired_noise_water, "Smoke test finds a point the retired noise terrain would have classified as water")
	var invisible_water_test_pos := IsoMath.grid_to_world(noise_water_grid.x, noise_water_grid.y)
	assert(not greenward.is_water_world(invisible_water_test_pos), "Removed procedural water noise cannot create invisible water")
	assert(greenward.is_walkable(invisible_water_test_pos), "Area remains walkable where no authored water zone exists")
	var water_zones := Node2D.new()
	water_zones.name = "WaterZones"
	greenward.navigation_component.add_child(water_zones)
	var authored_pond := Marker2D.new()
	authored_pond.set_meta("grid_position", Vector2(2.0, 3.0))
	authored_pond.set_meta("radius", 1.5)
	water_zones.add_child(authored_pond)
	var authored_pond_position := IsoMath.grid_to_world(2.0, 3.0)
	assert(greenward.is_water_world(authored_pond_position), "Authored water zones remain recognized")
	assert(not greenward.is_walkable(authored_pond_position), "Authored water remains impassable away from a bridge")
	greenward.water_and_bridges.register_bridge(Vector2(2.0, 3.0))
	assert(greenward.is_walkable(authored_pond_position), "Authored bridge registration restores water traversal")
	assert(greenward._prop_kind_counts.is_empty(), "Greenward contains no code-composed environment props")
	assert(greenward._interactive_props.is_empty(), "Greenward contains no generated interactive clutter")
	for chunk_data in greenward.loaded_chunks.values():
		assert(chunk_data.get("terrain") == null and chunk_data.get("water") == null and chunk_data.get("props", []).is_empty(), "Greenward chunk bookkeeping contains no generated art")
	print("GREENWARD_AUTHORED_TREE_PASS village=gameplay_only npcs=", greenward.npcs.size(), " authored_trees=", authored_tree_count, " hidden_placeholder_props=", hidden_placeholder_count)
	greenward.queue_free()
	await get_tree().process_frame

	for region_id in LANDMARKS:
		var world := WORLD_SCENE.instantiate() as GreenwardWorld
		world.region_id = region_id
		add_child(world)
		await get_tree().process_frame
		await get_tree().process_frame
		var spec: Array = LANDMARKS[region_id]
		var landmark := world.get_node("Entities").get_node_or_null(str(spec[0])) as Node2D
		assert(landmark != null, "Landmark instantiated for " + region_id)
		var region: Dictionary = ContentDB.get_region(region_id)
		var expected := Vector2.ZERO
		for poi in region.get("pois", []):
			if str(poi.get("id", "")) == str(spec[1]):
				var grid: Array = poi.get("grid", [0, 0])
				expected = IsoMath.grid_to_world(float(grid[0]), float(grid[1]))
				break
		assert(landmark.position.distance_to(expected) < 0.01, "Landmark anchored to POI for " + region_id)
		var expected_npcs := 0
		for poi in region.get("pois", []):
			if str(poi.get("type", "")) == "npc":
				expected_npcs += 1
		assert(world.npcs.size() == expected_npcs, "NPC POIs spawned for " + region_id)
		assert(world._portals.size() == region.get("connections", []).size(), "Gameplay portals remain for " + region_id)
		assert(world._prop_kind_counts.is_empty(), "No procedural POI dressing remains for " + region_id)
		assert(world._interactive_props.is_empty(), "No generated interactive clutter remains for " + region_id)
		assert(world.loaded_chunks.size() > 0, "Chunk streaming bookkeeping remains active for " + region_id)
		for chunk_data in world.loaded_chunks.values():
			assert(chunk_data.get("terrain") == null and chunk_data.get("water") == null and chunk_data.get("props", []).is_empty(), "No generated chunk art is materialized for " + region_id)
		print("ACT1_WORLD_COMPOSITION_PASS ", region_id, " landmark=", landmark.position, " npcs=", world.npcs.size(), " generated_props=0")
		world.queue_free()
		await get_tree().process_frame
	print("ACT1_WORLD_COMPOSITION_PASS areas=", LANDMARKS.size())
	get_tree().quit()
