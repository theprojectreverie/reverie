class_name CastleExpansionComponent
extends Node2D
## Scene composition root for the Royal Gardens expansion.
## Child components own the approach dressing and cache reward.
## Travel gates are authored in RoyalGardensGateAssembly, not spawned here.

func _ready() -> void:
	for component_name in ["ApproachBuilder", "CacheSpawner", "ExpansionInteractables"]:
		if get_node_or_null(component_name) == null:
			push_error("Castle expansion is missing component: %s" % component_name)
