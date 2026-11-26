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
	var failed := 0
	for sample in samples:
		var result: String = locomotion._surface_at(sample[0], "training_ground")
		if result != sample[1]:
			failed += 1
			push_error("Expected %s, got %s" % [sample[1], result])
		else:
			print("PASS surface: " + result)
	var audio = get_tree().root.get_node("AudioDirector")
	for sample in samples:
		audio.play_variant(locomotion._surface_at(sample[0], "training_ground"))
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