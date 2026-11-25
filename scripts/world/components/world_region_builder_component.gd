class_name WorldRegionBuilderComponent
extends Node
## Spawns authored Act I landmark scenes, content-backed NPCs and gameplay portals.
## Environmental dressing is supplied by authored artwork, never runtime generators.

var world: GreenwardWorld

const ACT1_LANDMARK_SCENES := {
	"royal_gate": preload("res://scenes/world/act1_areas/royal_gate_landmark.tscn"),
	"willow_fields": preload("res://scenes/world/act1_areas/willow_fields_landmark.tscn"),
	"elderwood_grove": preload("res://scenes/world/act1_areas/elderwood_grove_landmark.tscn"),
	"forsaken_ruins": preload("res://scenes/world/act1_areas/forsaken_ruins_landmark.tscn"),
	"ruined_tower": preload("res://scenes/world/act1_areas/ruined_tower_landmark.tscn"),
}

const ACT1_LANDMARK_POI_IDS := {
	"royal_gate": "royal_gate_landmark",
	"willow_fields": "willow_fields_windmill",
	"elderwood_grove": "ancient_watch",
	"forsaken_ruins": "forsaken_arch",
	"ruined_tower": "ruined_tower_landmark",
}


func configure(owner_world: GreenwardWorld) -> void:
	world = owner_world


func build_generic_region() -> void:
	if world == null:
		return
	var pois: Variant = world.region.get("pois", [])
	if typeof(pois) != TYPE_ARRAY:
		pois = []

	var landmark_scene := ACT1_LANDMARK_SCENES.get(world.region_id) as PackedScene
	if landmark_scene != null and world.entities != null:
		var landmark_assembly := landmark_scene.instantiate() as Node2D
		if landmark_assembly != null:
			var landmark_poi_id := str(ACT1_LANDMARK_POI_IDS.get(world.region_id, ""))
			for poi in pois:
				if typeof(poi) != TYPE_DICTIONARY or str(poi.get("id", "")) != landmark_poi_id:
					continue
				var grid: Variant = poi.get("grid", [])
				if typeof(grid) == TYPE_ARRAY and grid.size() == 2:
					landmark_assembly.position = IsoMath.grid_to_world(float(grid[0]), float(grid[1]))
				break
			landmark_assembly.z_as_relative = true
			world.entities.add_child(landmark_assembly)

	# NPC POIs are content-backed characters with dialogue resources.
	for poi in pois:
		if typeof(poi) != TYPE_DICTIONARY or str(poi.get("type", "")) != "npc":
			continue
		var npc_grid: Variant = poi.get("grid", [8, 8])
		if typeof(npc_grid) != TYPE_ARRAY or npc_grid.size() != 2:
			continue
		var npc_palette: Variant = poi.get("palette", {})
		var palette: Dictionary = npc_palette if typeof(npc_palette) == TYPE_DICTIONARY else {}
		world._spawn_npc(
			str(poi.get("npc_id", poi.get("id", "road_npc"))),
			str(poi.get("name", "Wayfarer")),
			str(poi.get("dialogue_id", "")),
			Vector2(float(npc_grid[0]), float(npc_grid[1])),
			palette,
			str(poi.get("race", "Human")),
			str(poi.get("role", ""))
		)


func _has_authored_portal(connection_id: String) -> bool:
	if world == null or connection_id.is_empty():
		return false
	for node in world.find_children("*", "RegionPortal", true, false):
		var portal := node as RegionPortal
		if portal != null and portal.connection_id == connection_id:
			return true
	return false


func spawn_region_portals() -> void:
	if world == null:
		return
	var connections: Variant = world.region.get("connections", [])
	if typeof(connections) != TYPE_ARRAY:
		return
	var entry_points: Variant = world.region.get("entry_points", {})
	var entry_dict: Dictionary = entry_points if typeof(entry_points) == TYPE_DICTIONARY else {}
	for connection in connections:
		if typeof(connection) != TYPE_DICTIONARY:
			continue
		var connection_id := str(connection.get("id", ""))
		# Authored scene instances take precedence over data-driven fallback
		# spawns. This lets hand-placed gates coexist with the generic builder
		# without duplicate interactables or doubled portal artwork.
		if _has_authored_portal(connection_id):
			continue
		var via := str(connection.get("via", ""))
		var grid: Variant = entry_dict.get(via, null)
		if typeof(grid) != TYPE_ARRAY or grid.size() != 2:
			continue
		var portal := GreenwardWorld.REGION_PORTAL_SCENE.instantiate() as RegionPortal
		portal.setup(world.region_id, connection)
		portal.position = IsoMath.grid_to_world(float(grid[0]), float(grid[1]))
		world.entities.add_child(portal)
		world.register_portal(portal)
