class_name CastleExpansionPortalComponent
extends Node
## Places the Royal Road gate in the expansion's dedicated interactables layer.

const PORTAL_SCENE: PackedScene = preload("res://scenes/world/region_portal.tscn")


func _ready() -> void:
	var region: Dictionary = ContentDB.get_region("castle_royal_gardens")
	var entries: Dictionary = region.get("entry_points", {})
	var layer := _props_layer()
	if layer == null:
		return
	for raw_connection in region.get("connections", []):
		if typeof(raw_connection) != TYPE_DICTIONARY:
			continue
		var connection: Dictionary = raw_connection
		if str(connection.get("to", "")) != "royal_gate":
			continue
		var via := str(connection.get("via", ""))
		var grid: Variant = entries.get(via, null)
		if typeof(grid) != TYPE_ARRAY or grid.size() != 2:
			push_warning("Royal Gardens Royal Road gate has no valid entry point: " + via)
			continue
		var portal := PORTAL_SCENE.instantiate() as RegionPortal
		if portal == null:
			continue
		portal.setup("castle_royal_gardens", connection)
		portal.position = IsoMath.grid_to_world(float(grid[0]), float(grid[1]))
		layer.add_child(portal)


func _props_layer() -> Node2D:
	var root := get_parent() as Node2D
	if root == null:
		push_error("Castle expansion portal requires its authored composition root.")
		return null
	var layer := root.get_node_or_null("ExpansionInteractables") as Node2D
	if layer == null:
		push_error("Castle expansion is missing its authored ExpansionInteractables layer.")
	return layer
