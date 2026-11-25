extends Node

const CASES := [
	{"name": "Greenward/Elderwood", "path": "res://scenes/world/greenward_world.tscn", "region": "elderwood_grove", "runtime": "WorldRuntime"},
	{"name": "Royal Gardens", "path": "res://scenes/world/castle_royal_gardens.tscn", "region": "castle_royal_gardens", "runtime": "WorldRuntime"},
	{"name": "Gothic Castle", "path": "res://scenes/world/gothic_castle_boss_zone.tscn", "region": "gothic_castle_boss_zone", "runtime": ""}
]

func _ready() -> void:
	call_deferred("_run")

func _collect_portals(node: Node, result: Array[RegionPortal]) -> void:
	if node is RegionPortal:
		result.append(node as RegionPortal)
	for child in node.get_children():
		_collect_portals(child, result)

func _run() -> void:
	var failures: Array[String] = []
	for test_case in CASES:
		var packed := load(str(test_case.path)) as PackedScene
		if packed == null:
			failures.append("%s: scene failed to load" % test_case.name)
			continue
		var world := packed.instantiate()
		if world == null:
			failures.append("%s: scene failed to instantiate" % test_case.name)
			continue
		if world is GreenwardWorld:
			world.region_id = str(test_case.region)
		get_tree().root.add_child(world)
		var runtime_name := str(test_case.runtime)
		if not runtime_name.is_empty():
			var runtime := world.get_node_or_null(runtime_name)
			if runtime != null:
				runtime.set_process(false)
		await get_tree().process_frame
		await get_tree().physics_frame
		var region: Dictionary = ContentDB.get_region(str(test_case.region))
		var expected_ids: Array[String] = []
		for raw in region.get("connections", []):
			if typeof(raw) == TYPE_DICTIONARY:
				var connection: Dictionary = raw
				if region.get("entry_points", {}).has(str(connection.get("via", ""))):
					expected_ids.append(str(connection.get("id", "")))
		var portals: Array[RegionPortal] = []
		_collect_portals(world, portals)
		var actual_ids: Array[String] = []
		for portal in portals:
			actual_ids.append(portal.connection_id)
			if portal.region_id != str(test_case.region):
				failures.append("%s: wrong source region on %s" % [test_case.name, portal.connection_id])
			if portal.target_region.is_empty() or portal.entry_point.is_empty():
				failures.append("%s: incomplete destination on %s" % [test_case.name, portal.connection_id])
			if not portal.is_in_group("interactables"):
				failures.append("%s: portal %s missing interactables group" % [test_case.name, portal.connection_id])
		if portals.size() != expected_ids.size():
			failures.append("%s: expected %d portals, found %d" % [test_case.name, expected_ids.size(), portals.size()])
		for connection_id in expected_ids:
			if not actual_ids.has(connection_id):
				failures.append("%s: missing route %s" % [test_case.name, connection_id])
		print("%s: spawned=%d expected=%d ids=%s" % [test_case.name, portals.size(), expected_ids.size(), str(actual_ids)])
		world.queue_free()
		await get_tree().process_frame
	if failures.is_empty():
		print("PRODUCTION PORTAL SPAWN PATHS: PASS (all three live world scenes; route IDs, destinations and interactables group verified)")
		get_tree().quit(0)
	else:
		for failure in failures:
			push_error(failure)
		print("PRODUCTION PORTAL SPAWN PATHS: FAIL (%d issues)" % failures.size())
		get_tree().quit(1)
