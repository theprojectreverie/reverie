extends SceneTree

const SCENE := "res://scenes/world/six_zone_reverie/individual_zones/zone_02_royal_gate_standalone.tscn"

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	if OS.get_environment("REVERIE_E2E_DISABLE_LOCAL_SAVE") != "1":
		quit(2)
		return
	change_scene_to_file(SCENE)
	await scene_changed
	for i in range(5):
		await physics_frame
	var zone := current_scene
	var gate := zone.get_node("Zone/RoyalGate/Gate") as Node2D
	var ground := zone.get_node("Zone/GroundTiles/EditableTileMap") as TileMapLayer
	var threshold := zone.get_node("Zone/GroundTiles/RoyalGateThreshold") as Sprite2D
	var cell := ground.local_to_map(ground.to_local(gate.global_position))
	var tile_center := ground.to_global(ground.map_to_local(cell))
	var errors: Array[String] = []
	var gate_floor_offset := gate.global_position - threshold.global_position
	if gate.global_position.distance_to(threshold.global_position) > 0.01:
		errors.append("gate should be centered over the marble entrance landing: %s" % gate_floor_offset)
	if ground.get_cell_source_id(cell) < 0:
		errors.append("gate center has no underlying ground tile")
	var paving_samples := 0
	for x in [-80.0, 0.0, 80.0]:
		for y in [-32.0, 0.0, 32.0, 64.0, 96.0, 128.0]:
			var point := gate.global_position + Vector2(x, y)
			var floor_cell := ground.local_to_map(ground.to_local(point))
			if ground.get_cell_source_id(floor_cell) < 0:
				errors.append("white floor missing under gate approach at %s" % point)
			else:
				paving_samples += 1
	print("GATE MARBLE ALIGNMENT gate=", gate.global_position, " floor_anchor=", threshold.global_position, " offset=", gate_floor_offset, " samples=", paving_samples, " errors=", errors.size())
	for error in errors:
		push_error(error)
	zone.queue_free()
	for i in range(3):
		await process_frame
	root.get_node("AudioDirector").stop_all_audio_immediately()
	await create_timer(0.35).timeout
	quit(0 if errors.is_empty() else 1)
