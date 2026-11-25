extends Node

func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	var previous_region: String = GameState.session_domain.player_region
	var previous_position: Vector2 = GameState.session_domain.player_position
	var previous_has_position: bool = GameState.session_domain.has_player_position
	GameState.session_domain.player_region = "castle_royal_gardens"
	GameState.session_domain.has_player_position = true
	var castle_region: Dictionary = ContentDB.get_region("castle_royal_gardens")
	var full_bounds: Dictionary = castle_region.get("map_bounds", {})
	var castle_bounds: Dictionary = castle_region.get("map_view_bounds", {})
	var full_min: Array = full_bounds.get("min", [])
	var full_max: Array = full_bounds.get("max", [])
	var bounds_min: Array = castle_bounds.get("min", [])
	var bounds_max: Array = castle_bounds.get("max", [])
	assert(full_min.size() == 2 and full_max.size() == 2
		and Vector2(float(full_min[0]), float(full_min[1])).is_equal_approx(Vector2(-544.0, -714.0))
		and Vector2(float(full_max[0]), float(full_max[1])).is_equal_approx(Vector2(3800.0, 7200.0)),
		"Royal Gardens playable-world bounds remain aligned with CastleLayout")
	assert(bounds_min.size() == 2 and bounds_max.size() == 2
		and Vector2(float(bounds_min[0]), float(bounds_min[1])).is_equal_approx(Vector2(-320.0, 64.0))
		and Vector2(float(bounds_max[0]), float(bounds_max[1])).is_equal_approx(Vector2(1600.0, 1024.0)),
		"Royal Gardens map-view bounds frame the playable garden feature area")
	var world := Node2D.new()
	world.name = "MapCoordinateSmokeWorld"
	world.position = Vector2(-416.0, -150.0)
	world.scale = Vector2(1.65, 1.25)
	world.add_to_group("world")
	add_child(world)
	var player := Node2D.new()
	player.name = "MapCoordinateSmokePlayer"
	player.position = IsoMath.grid_to_world(29.38, 9.38)
	player.add_to_group("player")
	world.add_child(player)
	GameState.session_domain.player_position = player.position
	var canvas_scene := load("res://scenes/ui/components/act1_map_atlas.tscn") as PackedScene
	assert(canvas_scene != null, "Authored Act I node-map scene loads")
	var canvas := canvas_scene.instantiate() as Act1MapAtlas
	canvas.size = Vector2(620.0, 500.0)
	add_child(canvas)
	await get_tree().process_frame
	canvas.refresh_map()
	await get_tree().process_frame
	var expected_castle: Vector2 = Vector2(29.38, 9.38)
	assert(canvas.get_node("Regions/RoyalGardens/CurrentMarker").visible, "Royal Gardens node-map marks the active region")
	assert((canvas.get_node("Panorama") as TextureRect).texture != null, "Act I uses its authored panoramic pixel-art texture")
	for thumbnail_path in ["RoyalGardensThumb", "RoyalGateThumb", "WillowFieldsThumb", "ElderwoodGroveThumb", "ForsakenRuinsThumb", "RuinedTowerThumb"]:
		assert((canvas.get_node(thumbnail_path) as TextureRect).texture != null, "Region strip uses authored artwork: " + thumbnail_path)
	var map_scene := load("res://scenes/ui/map_screen.tscn") as PackedScene
	assert(map_scene != null, "Map screen scene loads")
	var map_screen := map_scene.instantiate() as MapScreen
	add_child(map_screen)
	await get_tree().process_frame
	assert(map_screen._map_canvas is Act1MapAtlas, "Playable MapScreen uses the authored node-based Act I atlas")
	assert((map_screen._map_canvas as Act1MapAtlas).has_signal("region_selected"), "MapScreen exposes node-based region selection")
	assert(map_screen._player_position_label.text == "Player: (29, 9)", "Royal Gardens map-screen coordinates use region-local position")
	var atlas := map_screen._map_canvas as Act1MapAtlas
	var tracked_child_count_before_switch := map_screen._tracked_box.get_child_count()
	atlas.set_selected_region("willow_fields")
	assert(map_screen._displayed_region_id == "willow_fields", "Selecting a region updates the MapScreen's displayed region")
	assert(map_screen._region_label.text == ContentDB.get_region("willow_fields").get("name", ""), "Selected region updates the region title")
	assert(map_screen._player_position_label.text == "Player: not in this region", "A remote region does not show the player's local coordinates")
	assert(map_screen._info_box.get_child_count() == ContentDB.get_region("willow_fields").get("pois", []).size() + 2, "Willow POIs replace old entries immediately")
	var willow_first_poi := (map_screen._info_box.get_child(2) as Button).text
	atlas.set_selected_region("elderwood_grove")
	assert(map_screen._displayed_region_id == "elderwood_grove", "Selecting another region replaces the displayed region")
	assert(map_screen._info_box.get_child_count() == ContentDB.get_region("elderwood_grove").get("pois", []).size() + 2, "Rapid region changes do not accumulate stale POI controls")
	assert((map_screen._info_box.get_child(2) as Button).text != willow_first_poi, "POI panel shows the newly selected region instead of retaining old entries")
	assert(map_screen._tracked_box.get_child_count() == tracked_child_count_before_switch, "Tracked quest panel does not accumulate stale controls on rapid region changes")
	await get_tree().process_frame
	atlas.set_selected_region("castle_royal_gardens")
	await get_tree().process_frame
	assert(map_screen._player_position_label.text == "Player: (29, 9)", "Returning to the current region restores the live coordinate readout")
	GameState.session_domain.player_region = "willow_fields"
	await get_tree().create_timer(0.2).timeout
	assert(map_screen._displayed_region_id == "willow_fields", "Map follows a live region transition when the previous current region was selected")
	assert(map_screen._region_label.text == ContentDB.get_region("willow_fields").get("name", ""), "Live region transition updates the region title")
	GameState.session_domain.player_region = "castle_royal_gardens"
	await get_tree().create_timer(0.2).timeout

	# Registered live quest targets are supplied in global space by their node;
	# the resolver must convert them into the same region-local frame.
	var live_target := Node2D.new()
	live_target.name = "MapCoordinateSmokeQuestTarget"
	live_target.position = IsoMath.grid_to_world(32.0, 11.0)
	world.add_child(live_target)
	var resolver := QuestNavigationResolver.new()
	resolver.register_nav_target("map_smoke_target", {
		"region_id": "castle_royal_gardens",
		"objective_id": "smoke_wolf",
		"node": live_target
	})
	var live_result: Dictionary = resolver._select_live_target(
		"smoke_quest", {"type": "kill", "target": "smoke_wolf"},
		"castle_royal_gardens", expected_castle
	)
	assert(live_result.get("local_pos", Vector2.ZERO).distance_to(live_target.position) < 0.02,
		"Royal Gardens live quest target converts global node position into region-local position")
	resolver.clear_registry()
	live_result.clear()
	resolver = null
	live_target.free()

	# Greenward has an identity world transform; ensure the conversion leaves
	# its existing coordinate behaviour unchanged.
	GameState.session_domain.player_region = "greenward"
	world.position = Vector2.ZERO
	world.scale = Vector2.ONE
	player.position = IsoMath.grid_to_world(8.0, 8.0)
	GameState.session_domain.player_position = player.position
	canvas.refresh_map()
	await get_tree().process_frame
	assert(not canvas.get_node("Regions/RoyalGardens/CurrentMarker").visible, "Act I node-map does not mislabel Greenward as an Act I region")
	print("MAP_COORDINATE_SMOKE_PASS castle=", expected_castle, " greenward=identity map frame", " map_screen=", map_screen._player_position_label.text)
	map_screen.free()
	canvas.free()
	world.free()
	GameState.session_domain.player_region = previous_region
	GameState.session_domain.player_position = previous_position
	GameState.session_domain.has_player_position = previous_has_position
	# Headless smoke tests quit before normal application shutdown. Release any
	# one-shot UI audio triggered by MapScreen's overlay-open animation so the
	# AudioDirector pool does not retain an active MP3 playback at process exit.
	AudioDirector.stop_all_audio_immediately()
	# Give the audio mixer a short drain window after stopping the MP3 playback.
	await get_tree().create_timer(0.35).timeout
	get_tree().quit(0)
