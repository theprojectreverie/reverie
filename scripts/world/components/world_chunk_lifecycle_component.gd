class_name WorldChunkLifecycleComponent
extends Node
## Retains region streaming bookkeeping without materializing generated scenery.

var world: GreenwardWorld


func configure(owner_world: GreenwardWorld) -> void:
	world = owner_world


## Suppress streamed tree props only where the authored Greenward village layout
## reserves space for buildings, paths, NPCs and its central clearing. The
## exclusion data is shared with VillageEnvironment's authored tree placement,
## so streamed content cannot contradict the scene's designed clearances.
func should_suppress_streamed_tree(kind: String, world_position: Vector2) -> bool:
	if world == null or world.region_id != "greenward":
		return false
	if kind not in ["glade_tree", "ancient_tree", "willow_tree", "birch_tree", "pine_tree", "blossom_tree", "dead_tree"]:
		return false
	var village := world.get_node_or_null("Village") as VillageEnvironment
	if village == null or not village.layout_config is VillageLayoutConfig:
		return false
	var config := village.layout_config as VillageLayoutConfig
	for zone_value in config.exclusion_zones:
		if typeof(zone_value) != TYPE_DICTIONARY:
			continue
		var zone: Dictionary = zone_value
		var center_value: Variant = zone.get("center", Vector2.ZERO)
		var center := center_value as Vector2 if center_value is Vector2 else Vector2.ZERO
		match str(zone.get("type", "circle")):
			"circle":
				if world_position.distance_to(center) <= float(zone.get("radius", 0.0)):
					return true
			"rect":
				var size_value: Variant = zone.get("size", Vector2.ZERO)
				var size := size_value as Vector2 if size_value is Vector2 else Vector2.ZERO
				var half := size * 0.5
				if absf(world_position.x - center.x) <= half.x and absf(world_position.y - center.y) <= half.y:
					return true
	return false


func load_chunk(coord: Vector2i) -> void:
	if world == null or world.loaded_chunks.has(coord):
		return
	# Chunk coordinates remain tracked for region streaming/navigation only.
	# Terrain, water and scatter props must come from authored scenes/assets.
	world.loaded_chunks[coord] = {
		"terrain": null,
		"water": null,
		"props": [],
	}


func unload_chunk(coord: Vector2i) -> void:
	if world == null or not world.loaded_chunks.has(coord):
		return
	var data: Dictionary = world.loaded_chunks[coord]
	for key in ["terrain", "water"]:
		var node: Node = data.get(key, null)
		if node != null and is_instance_valid(node):
			node.queue_free()
	for prop in data.get("props", []):
		if is_instance_valid(prop):
			prop.queue_free()
	world.loaded_chunks.erase(coord)
