extends Node

const REGION_SCENE := preload("res://scenes/world/greenward_world.tscn")
const GARDENS_SCENE := preload("res://scenes/world/castle_royal_gardens.tscn")
const BOSS_SCENE := preload("res://scenes/world/gothic_castle_boss_zone.tscn")

func _ready() -> void:
	call_deferred("_run")

func _run() -> void:
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://resources/data/regions.json"))
	assert(typeof(parsed) == TYPE_DICTIONARY, "regions data parses")
	var regions: Dictionary = parsed
	var graph := RegionGraph.new(regions)
	var tested := 0
	var failures: Array[String] = []
	for from_id in graph.region_ids():
		for connection in graph.connections_from(from_id):
			if typeof(connection) != TYPE_DICTIONARY:
				continue
			var target := str(connection.get("to", ""))
			var entry := str(connection.get("entry", ""))
			if target.is_empty() or entry.is_empty():
				continue
			var definition: Dictionary = regions.get(target, {})
			var entries: Dictionary = definition.get("entry_points", {})
			if not entries.has(entry):
				failures.append("%s -> %s missing entry %s" % [from_id, target, entry])
				continue
			var scene: PackedScene = GARDENS_SCENE if target == "castle_royal_gardens" else (BOSS_SCENE if target == "gothic_castle_boss_zone" else REGION_SCENE)
			var world := scene.instantiate() as Node2D
			assert(world != null, "Destination world instantiates: " + target)
			if "region_id" in world:
				world.set("region_id", target)
			if "entry_point" in world:
				world.set("entry_point", entry)
			get_tree().root.add_child(world)
			var runtime := world.get_node_or_null("WorldRuntime")
			if runtime != null:
				runtime.set_process(false)
			await get_tree().process_frame
			await get_tree().physics_frame
			var player: Node2D = world.get("player") as Node2D
			if player == null:
				failures.append("%s via %s: player missing" % [target, entry])
			else:
				var expected_array: Array = entries[entry]
				var expected := IsoMath.grid_to_world(float(expected_array[0]), float(expected_array[1]))
				var recorded_spawn := GameState.session_domain.region_position(target)
				var spawn_exact := recorded_spawn.distance_to(expected) < 0.1
				var current_position := player.position
				var walkable := false
				var collision_hits := -1
				var collision_node := player.get_node_or_null("CollisionShape2D") as CollisionShape2D
				if collision_node != null and collision_node.shape != null:
					var query := PhysicsShapeQueryParameters2D.new()
					query.shape = collision_node.shape
					query.transform = collision_node.global_transform
					query.collision_mask = player.collision_mask
					query.collide_with_bodies = true
					query.collide_with_areas = false
					query.exclude = [player.get_rid()]
					collision_hits = get_viewport().world_2d.direct_space_state.intersect_shape(query, 8).size()
				var dry := true
				if world.has_method("is_water_world"):
					dry = not bool(world.call("is_water_world", current_position))
				elif world.has_method("is_walkable"):
					dry = bool(world.call("is_walkable", current_position))
				walkable = dry and collision_hits == 0
				if not spawn_exact:
					failures.append("%s via %s: recorded initial spawn mismatch expected=%s recorded=%s" % [target, entry, expected, recorded_spawn])
				if not walkable:
					failures.append("%s via %s: live player position is water/blocked at %s (collision_hits=%d)" % [target, entry, current_position, collision_hits])
				if spawn_exact and walkable:
					print("ENTRY SPAWN PASS: %s via %s | spawn=%s live=%s collision_hits=%d" % [target, entry, recorded_spawn, current_position, collision_hits])
			tested += 1
			world.queue_free()
			await get_tree().process_frame
	assert(tested > 0, "At least one region entry spawn must be tested")
	for failure in failures:
		push_error("ENTRY SPAWN: " + failure)
	print("ACT I ENTRY SPAWN AUDIT: %s (%d destination entries)" % ["PASS" if failures.is_empty() else "FAIL", tested])
	get_tree().quit(0 if failures.is_empty() else 1)
