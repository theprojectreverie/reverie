extends Node

func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	var packed: PackedScene = load("res://scenes/world/region_portal.tscn")
	assert(packed != null, "portal scene unavailable")
	var checked := 0
	var seen_ids: Dictionary = {}
	for source_id in ContentDB.regions.keys():
		var source: Dictionary = ContentDB.get_region(str(source_id))
		var connections: Array = source.get("connections", [])
		for connection_variant in connections:
			var connection: Dictionary = connection_variant
			var connection_id := str(connection.get("id", ""))
			var target_id := str(connection.get("to", ""))
			var entry_id := str(connection.get("entry", ""))
			assert(not connection_id.is_empty(), "connection missing id in " + str(source_id))
			assert(not seen_ids.has(connection_id), "duplicate connection id " + connection_id)
			seen_ids[connection_id] = true
			assert(ContentDB.regions.has(target_id), "unknown target " + target_id)
			var target: Dictionary = ContentDB.get_region(target_id)
			assert(target.get("entry_points", {}).has(entry_id), "missing target entry " + target_id + ":" + entry_id)
			var portal := packed.instantiate() as RegionPortal
			assert(portal != null)
			portal.setup(str(source_id), connection)
			add_child(portal)
			await get_tree().process_frame
			assert(portal.region_id == str(source_id))
			assert(portal.connection_id == connection_id)
			assert(portal.target_region == target_id)
			assert(portal.entry_point == entry_id)
			assert(portal.get_node("Label").text == str(connection.get("label", "Travel")))
			portal.queue_free()
			checked += 1
			await get_tree().process_frame
	assert(checked == 16, "expected 16 authored connections; got " + str(checked))
	print("ACT I PORTAL DATA/SCENE INTEGRATION: PASS (" + str(checked) + " live scene instances; all target entries valid)")
	get_tree().quit(0)
