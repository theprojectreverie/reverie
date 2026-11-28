extends Node

var failures := 0
func check(ok: bool, label: String) -> void:
	print("WADE ", label, " = ", ok)
	if not ok:
		failures += 1

func _ready() -> void:
	call_deferred("_run")

func _run() -> void:
	var map := load("res://scenes/world/six_zone_reverie/drowned_orchid_ruins/elderwood_flooded_landscape.tscn").instantiate() as Node2D
	add_child(map)
	var player := load("res://scenes/characters/player.tscn").instantiate() as Player
	add_child(player)
	player.set_physics_process(false)
	var locomotion := player.get_node("LocomotionComponent") as PlayerLocomotionComponent
	locomotion.set_physics_process(false)
	player.set_avatar("kael")
	await get_tree().physics_frame
	var northern := map.get_node("NorthernMirror") as Polygon2D
	var west := map.get_node("WestFloodplain") as Polygon2D
	var east := map.get_node("EasternLake") as Polygon2D
	var point := northern.to_global(Vector2(-250, 600))
	var west_point := west.to_global(Vector2(-1950, 1650))
	check(locomotion._water_at(point), "Northern Mirror wade detection")
	check(locomotion._water_at(west_point), "West Floodplain wade detection")
	check(locomotion._water_at(east.to_global(Vector2(2000, 1550))), "Eastern lake now wadeable")
	check(not locomotion._water_at(Vector2(9000, 9000)), "Dry ground excluded")
	check(map.get_node("NorthernMirrorCollision").collision_layer == 0, "Shallow pool barrier removed")
	check(map.get_node("EasternLakeCollision").collision_layer == 0, "Eastern pool barrier removed")
	check(map.get_node("SouthernLagoonCollision").collision_layer == 0, "Southern pool barrier removed")
	var query := PhysicsPointQueryParameters2D.new()
	query.position = point
	query.collision_mask = 1
	var hits := player.get_world_2d().direct_space_state.intersect_point(query)
	print("Northern blockers: ", hits.map(func(hit): return str(hit.collider)))
	check(hits.is_empty(), "Northern interior walkable")
	query.position = west_point
	hits = player.get_world_2d().direct_space_state.intersect_point(query)
	print("Western blockers: ", hits.map(func(hit): return str(hit.collider)))
	check(hits.is_empty(), "Western interior walkable")
	player.global_position = point
	var presentation := player.get_node("PresentationComponent")
	var sprite := player.get_node("ActorVisual/FrameSprite") as Sprite2D
	var original := sprite.material
	presentation.update_water_visual(true)
	check(sprite.material is ShaderMaterial, "Character waterline material")
	if sprite.material is ShaderMaterial:
		check(float(sprite.material.get_shader_parameter("sink_pixels")) > 0.0, "Frame scaled submersion")
	check(player.get_node("WaterSurface").visible, "Ripple visible")
	presentation.update_water_visual(false)
	check(sprite.material == original, "Dry material restored")
	check(not player.get_node("WaterSurface").visible, "Ripple hidden")
	var deep := locomotion._water_depth_at(point)
	var center := northern.to_global(Vector2(-250, 600))
	var edge := northern.to_global(northern.polygon[0])
	var shore := edge.lerp(center, 0.035)
	var shallow := locomotion._water_depth_at(shore)
	check(deep > 0.95 and shallow > 0.0 and shallow < deep, "Gradual shoreline depth")
	presentation.update_water_visual(true, shallow)
	var shallow_sink := float(sprite.material.get_shader_parameter("sink_pixels"))
	presentation.update_water_visual(true, deep)
	check(float(sprite.material.get_shader_parameter("sink_pixels")) > shallow_sink, "Submersion scales with shoreline depth")
	presentation.update_water_visual(false)
	var burst := player.get_node("WaterSurface/RippleGeometry/SplashWake/AnimationPlayer") as AnimationPlayer
	AudioDirector._last_sfx_variant.erase("water_entry")
	AudioDirector._last_sfx_variant.erase("water_step")
	locomotion._sync_water_state(deep, true)
	check(AudioDirector._last_sfx_variant.has("water_entry"), "Entry plays dedicated splash")
	check(burst.is_playing() and burst.current_animation == "entry", "Entry ripple burst")
	var entry_variant: int = AudioDirector._last_sfx_variant.get("water_entry", 0)
	locomotion._sync_water_state(deep, true)
	check(AudioDirector._last_sfx_variant.get("water_entry", 0) == entry_variant, "Entry does not repeat")
	locomotion._water_step_timer = 0.0
	locomotion._tick_water_foley(1.0, false)
	check(not AudioDirector._last_sfx_variant.has("water_step"), "Idle in water is silent")
	locomotion._tick_water_foley(1.0, true)
	check(AudioDirector._last_sfx_variant.has("water_step"), "Moving triggers water footsteps")
	check(burst.is_playing() and burst.current_animation == "step", "Movement ripple burst")
	var variant: int = AudioDirector._last_sfx_variant.get("water_step", 0)
	locomotion._tick_water_foley(1.0, true)
	check(AudioDirector._last_sfx_variant.get("water_step", 0) != variant, "Splash variation")
	locomotion._sync_water_state(0.0, false)
	check(not burst.is_playing() and not player.get_node("WaterSurface").visible, "Leaving water stops ripples")
	for category in ["water_step", "water_entry"]:
		for index in range(1, int(AudioDirector.EXTENDED_SFX[category]) + 1):
			var path := "res://assets/audio/sfx/extended/%s/%s_%d.wav" % [category, category, index]
			check(ResourceLoader.exists(path) and load(path) is AudioStream, "Imported " + path.get_file())
	player.queue_free()
	map.queue_free()
	await get_tree().process_frame
	print("WADING_SMOKE failures=", failures)
	get_tree().quit(failures)
