extends Node

func _ready() -> void:
	call_deferred("_run")

func _run() -> void:
	var world := Node2D.new()
	add_child(world)

	var player := load("res://scenes/characters/player.tscn").instantiate() as CharacterBody2D
	world.add_child(player)
	player.set_physics_process(false)
	var locomotion = player.get_node("LocomotionComponent")
	locomotion.set_physics_process(false)
	var cases := [
		["res://scenes/world/six_zone_reverie/terrain/willow_flat_grass.tscn", "grass_step"],
		["res://scenes/world/reverie_pack/Royal_Gardens/Terrain/soil_garden_01.tscn", "dirt_step"],
		["res://scenes/world/six_zone_reverie/garden_stone_path.tscn", "stone_step"],
	]
	var samples: Array = []
	for i in range(cases.size()):
		var tile := load(cases[i][0]).instantiate() as Node2D
		tile.position = Vector2(i * 256, 0)
		world.add_child(tile)
		var sprite: Sprite2D
		for child in tile.get_children():
			if child is Sprite2D:
				sprite = child
				break
		samples.append([sprite.to_global(sprite.get_rect().get_center()), cases[i][1]])
	# Real authored atlas cells, including road overlays above grass.
	var layer := TileMapLayer.new()
	layer.tile_set = load("res://scenes/world/six_zone_reverie/tilemaps/willow_refined_ground_tileset.tres")
	layer.position = Vector2(1200, 0)
	layer.z_index = 3
	world.add_child(layer)
	var expected := {"grass_step": -1, "dirt_step": -1, "stone_step": -1}
	for i in range(layer.tile_set.get_source_count()):
		var source_id := layer.tile_set.get_source_id(i)
		var source := layer.tile_set.get_source(source_id) as TileSetAtlasSource
		if source == null or source.texture == null:
			continue
		var material: String = locomotion._surface_material(source.texture.resource_path)
		if expected.has(material) and expected[material] == -1:
			expected[material] = source_id
	for material in expected:
		var source_id: int = expected[material]
		if source_id < 0:
			push_error("Missing atlas fixture: " + material)
			get_tree().quit(1)
			return
		var coord := Vector2i(samples.size() * 4, 0)
		var source := layer.tile_set.get_source(source_id) as TileSetAtlasSource
		layer.set_cell(coord, source_id, source.get_tile_id(0))
		samples.append([layer.to_global(layer.map_to_local(coord)), material])
	var wood := Sprite2D.new()
	wood.texture = load("res://assets/tutorial_prologue/Reverie_Tutorial_Asset_Pack/Bedroom/wood_floor_tile_source.png")
	wood.position = Vector2(2400, 0)
	world.add_child(wood)
	samples.append([wood.to_global(wood.get_rect().get_center()), "wood_step"])
	samples.append([Vector2(9000, 9000), "dirt_step"])
	var failed := 0
	for sample in samples:
		var result: String = locomotion._surface_at(sample[0], "willow_fields")
		if result != sample[1]:
			failed += 1
			push_error("Expected %s, got %s" % [sample[1], result])
		else:
			print("PASS surface: " + result)
	var audio = get_tree().root.get_node("AudioDirector")
	for sample in samples:
		audio.play_variant(locomotion._surface_at(sample[0], "willow_fields"))
		await get_tree().process_frame
		var playing := false
		for p in audio._sfx_players:
			if p.playing and p.stream != null and p.stream.resource_path.contains(sample[1]):
				playing = true
		if not playing:
			failed += 1
			push_error("Footstep not playing: " + sample[1])
		else:
			print("PASS playback: " + sample[1])
	audio.stop_all_audio_immediately()
	await get_tree().create_timer(0.35).timeout
	print("FOOTSTEP SURFACE TEST: %d failures" % failed)
	get_tree().quit(failed)