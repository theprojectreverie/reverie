extends Node

var arrivals: Array[String] = []

func _ready() -> void:
	call_deferred("_run")

func _run() -> void:
	var session := get_node("WorldSession") as GameWorldSessionComponent
	var host := get_node("WorldHost") as Node2D
	assert(session != null and host != null)
	await get_tree().process_frame
	var source_world := session.build_world("castle_royal_gardens", "")
	assert(source_world != null and session.current_region_id == "castle_royal_gardens")
	await get_tree().process_frame
	await get_tree().physics_frame
	var source_player: Node2D = source_world.get("player") as Node2D
	assert(source_player != null, "Source garden must spawn its player")
	session.region_arrived.connect(func(id: String, _name: String) -> void: arrivals.append(id))
	var result := session.transition_to("royal_gate", "gate_arrival")
	assert(bool(result.get("ok", false)), "Connected transition must succeed: %s" % result)
	assert(session.current_region_id == "royal_gate")
	assert(session.world != source_world and session.world == result.get("world"))
	assert(session.world.get_parent() == host)
	var destination_player: Node2D = session.world.get("player") as Node2D
	assert(destination_player != null, "Destination must spawn its player")
	var entries: Dictionary = ContentDB.get_region("royal_gate").get("entry_points", {})
	var grid: Array = entries.get("gate_arrival", [])
	assert(grid.size() == 2)
	var expected := IsoMath.grid_to_world(float(grid[0]), float(grid[1]))
	assert(destination_player.position.distance_to(expected) < 0.1, "Destination player must use requested entry point")
	assert(arrivals == ["royal_gate"], "Exactly one arrival signal must be emitted")
	assert(host.get_child_count() == 1 and host.get_child(0) == session.world, "WorldHost must contain only the destination")
	var blocked := session.transition_to("gothic_castle_boss_zone", "gate_arrival")
	assert(not bool(blocked.get("ok", false)), "Non-adjacent route must be rejected")
	assert(session.current_region_id == "royal_gate" and arrivals.size() == 1, "Rejected route must preserve active destination")

	# Exercise the authored return connection, not a fabricated direct jump.
	var gate_definition: Dictionary = ContentDB.get_region("royal_gate")
	var return_connection: Dictionary = {}
	for connection_variant in gate_definition.get("connections", []):
		var connection: Dictionary = connection_variant
		if str(connection.get("to", "")) == "castle_royal_gardens":
			return_connection = connection
			break
	assert(not return_connection.is_empty(), "Royal Gate must expose an authored return route to Royal Gardens")
	var return_entry := str(return_connection.get("entry", ""))
	var returned := session.transition_to("castle_royal_gardens", return_entry)
	assert(bool(returned.get("ok", false)), "Authored return transition must succeed: %s" % returned)
	assert(session.current_region_id == "castle_royal_gardens", "Return transition must restore Royal Gardens")
	assert(session.world != destination_player.get_parent().get_parent(), "Return trip must replace the Royal Gate world")
	var return_player: Node2D = session.world.get("player") as Node2D
	assert(return_player != null, "Return destination player missing")
	var garden_entries: Dictionary = ContentDB.get_region("castle_royal_gardens").get("entry_points", {})
	var return_grid: Array = garden_entries.get(return_entry, [])
	assert(return_grid.size() == 2, "Return destination entry must exist in Royal Gardens")
	var return_expected := IsoMath.grid_to_world(float(return_grid[0]), float(return_grid[1]))
	assert(return_player.position.distance_to(return_expected) < 0.1, "Return player must use the authored return entry")
	assert(arrivals == ["royal_gate", "castle_royal_gardens"], "Both arrival events must fire exactly once: " + str(arrivals))
	assert(host.get_child_count() == 1 and host.get_child(0) == session.world, "WorldHost must retain only the returned destination")

	# Walk the full authored Act I progression chain through real world swaps.
	var progression := ["royal_gate", "willow_fields", "elderwood_grove", "forsaken_ruins", "ruined_tower", "gothic_castle_boss_zone"]
	var previous_id := "castle_royal_gardens"
	for next_id in progression:
		var source_definition: Dictionary = ContentDB.get_region(previous_id)
		var chosen: Dictionary = {}
		for connection_variant in source_definition.get("connections", []):
			var connection: Dictionary = connection_variant
			if str(connection.get("to", "")) == next_id:
				chosen = connection
				break
		assert(not chosen.is_empty(), "Missing authored progression link: %s -> %s" % [previous_id, next_id])
		var destination_entry := str(chosen.get("entry", ""))
		var chain_result := session.transition_to(next_id, destination_entry)
		assert(bool(chain_result.get("ok", false)), "Progression transition failed %s -> %s: %s" % [previous_id, next_id, chain_result])
		assert(session.current_region_id == next_id and session.world == chain_result.get("world"), "Active region/world mismatch at " + next_id)
		var chain_player: Node2D = session.world.get("player") as Node2D
		assert(chain_player != null, "Player missing after arrival at " + next_id)
		var destination_entries: Dictionary = ContentDB.get_region(next_id).get("entry_points", {})
		var destination_grid: Array = destination_entries.get(destination_entry, [])
		assert(destination_grid.size() == 2, "Missing destination spawn key %s:%s" % [next_id, destination_entry])
		var destination_expected := IsoMath.grid_to_world(float(destination_grid[0]), float(destination_grid[1]))
		assert(chain_player.position.distance_to(destination_expected) < 0.1, "Wrong arrival spawn at " + next_id)
		assert(host.get_child_count() == 1 and host.get_child(0) == session.world, "Stale world remains mounted at " + next_id)
		previous_id = next_id
	assert(arrivals.size() == 8, "Expected two round-trip arrivals plus six progression arrivals; got %d" % arrivals.size())
	print("WORLD SESSION TRANSITION INTEGRATION: PASS | round_trip + full_act1_chain=", progression.size(), " | invalid route rejected | arrivals=", arrivals.size())

	# Explicitly release the final mounted world and session before exiting;
	# otherwise the test harness itself leaves live nodes for ObjectDB teardown.
	await get_tree().process_frame
	host.queue_free()
	session.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame
	get_tree().quit(0)
