class_name WorldNavigationComponent
extends Node2D
## Owns world-space walkability, water classification and bridge traversal data.

const DEFAULT_BRIDGE_RADIUS := 40.0

var world: Node2D
var elevation: FastNoiseLite
var bridge_positions: Array[Vector2] = []
var bridge_radius: float = DEFAULT_BRIDGE_RADIUS


func _ready() -> void:
	world = get_parent() as Node2D


func set_elevation_noise(noise: FastNoiseLite) -> void:
	elevation = noise


func add_bridge_position(grid_position: Vector2) -> void:
	bridge_positions.append(IsoMath.grid_to_world(grid_position.x, grid_position.y))


func is_water_world(world_pos: Vector2) -> bool:
	# Water must be authored as an explicit zone. Noise-based classification
	# belonged to the retired procedural terrain generator and would otherwise
	# create invisible impassable patches after its water visuals were removed.
	var grid := IsoMath.world_to_grid(world_pos)
	var zones := get_node_or_null("WaterZones") as Node2D
	if zones == null:
		return false
	for marker in zones.get_children():
		if not (marker is Marker2D):
			continue
		var grid_value: Variant = marker.get_meta("grid_position", null)
		var radius := float(marker.get_meta("radius", 0.0))
		if grid_value is Vector2 and radius > 0.0 and grid.distance_to(grid_value) < radius:
			return true
	return false


func is_walkable(world_pos: Vector2) -> bool:
	return not is_water_world(world_pos) or is_near_bridge(world_pos)


func is_near_bridge(world_pos: Vector2) -> bool:
	for bridge_position in bridge_positions:
		if world_pos.distance_to(bridge_position) <= bridge_radius:
			return true
	return false


func world_to_grid(world_pos: Vector2) -> Vector2:
	return IsoMath.world_to_grid(world_pos)


func get_water_level() -> float:
	if world == null:
		return -0.22
	var region: Dictionary = world.get("region")
	var biome: Variant = region.get("biome", {})
	if typeof(biome) != TYPE_DICTIONARY:
		biome = {}
	return float(biome.get("water_level", -0.22))


func get_bridge_positions() -> Array:
	return bridge_positions


func get_bridge_radius() -> float:
	return bridge_radius
