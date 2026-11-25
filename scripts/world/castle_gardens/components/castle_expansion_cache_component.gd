class_name CastleExpansionCacheComponent
extends Node
## Optional legacy cache spawner. Retired placement markers remain dormant.

const GATHER_SCENE: PackedScene = preload("res://scenes/world/interactive_prop.tscn")
const CACHE_VISUAL: PackedScene = preload("res://scenes/world/castle_gardens/components/castle_seal_cache_visual.tscn")


func _ready() -> void:
	var root := get_parent() as Node2D
	var placements := root.get_node_or_null("ApproachPlacements") as Node2D if root != null else null
	var interactables := root.get_node_or_null("ExpansionInteractables") as Node2D if root != null else null
	if placements == null or interactables == null:
		push_error("Castle expansion cache requires authored placements and ExpansionInteractables.")
		return
	var marker := placements.get_node_or_null("GardenerSealCache") as Marker2D
	if marker == null or str(marker.get_meta("placement_type", "disabled")) != "collectible":
		return
	var grid_value: Variant = marker.get_meta("grid_position", null)
	var rewards_value: Variant = marker.get_meta("rewards", {})
	var rewards: Dictionary = rewards_value if typeof(rewards_value) == TYPE_DICTIONARY else {}
	var item_id := str(marker.get_meta("item_id", ""))
	var display_name := str(marker.get_meta("display_name", ""))
	var description := str(marker.get_meta("description", ""))
	var collectible_id := str(marker.get_meta("collectible_id", ""))
	var quantity := int(marker.get_meta("quantity", 1))
	if not (grid_value is Vector2) or item_id.is_empty() or display_name.is_empty() or collectible_id.is_empty() or rewards.is_empty():
		push_error("GardenerSealCache marker is missing required collectible metadata.")
		return
	var prop := GATHER_SCENE.instantiate() as InteractiveProp
	if prop == null:
		push_error("Castle expansion cache could not instantiate its collectible scene.")
		return
	prop.setup(item_id, IsoMath.grid_to_world(grid_value.x, grid_value.y), display_name, description, quantity)
	prop.configure_collectible(collectible_id, rewards, display_name)
	var visual := CACHE_VISUAL.instantiate() as Node2D
	if visual == null:
		push_error("Castle expansion cache could not instantiate its authored visual scene.")
		return
	visual.name = "AuthoredVisual"
	prop.add_child(visual)
	interactables.add_child(prop)
