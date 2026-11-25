extends SceneTree

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://resources/data/regions.json"))
	assert(typeof(parsed) == TYPE_DICTIONARY, "regions.json parses")
	var regions: Dictionary = parsed
	var graph := RegionGraph.new(regions)
	var errors := graph.validate()
	for error in errors:
		push_error("ACT1_REGION_GRAPH: " + error)
	assert(graph.can_travel("greenward", "castle_royal_gardens"), "Greenward connects into Royal Gardens")
	assert(graph.can_travel("castle_royal_gardens", "greenward"), "Royal Gardens can return to Greenward")
	var chain := ["castle_royal_gardens", "royal_gate", "willow_fields", "elderwood_grove", "forsaken_ruins", "ruined_tower", "gothic_castle_boss_zone"]
	for index in range(chain.size() - 1):
		assert(graph.can_travel(chain[index], chain[index + 1]), "Act I road connection " + chain[index] + " -> " + chain[index + 1])
		var from_region: Dictionary = regions.get(chain[index], {})
		var connection: Dictionary = {}
		for entry in from_region.get("connections", []):
			if str(entry.get("to", "")) == chain[index + 1]:
				connection = entry
				break
		var result := graph.resolve_transition(chain[index], str(connection.get("id", "")))
		assert(bool(result.get("valid", false)), "Act I transition endpoints resolve: " + chain[index] + " -> " + chain[index + 1])
	assert(errors.is_empty(), "RegionGraph validation has no errors")
	print("ACT1_REGION_GRAPH_PASS regions=", graph.region_ids().size(), " connections=", graph.summary().connection_count, " chain=", chain)
	quit(0 if errors.is_empty() else 1)
