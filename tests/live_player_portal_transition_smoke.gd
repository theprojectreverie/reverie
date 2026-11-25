extends Node

const GAME_SCENE := preload("res://scenes/game.tscn")
const PROGRESSION := [
	"royal_gate",
	"willow_fields",
	"elderwood_grove",
	"forsaken_ruins",
	"ruined_tower",
	"gothic_castle_boss_zone",
]
var arrival_events: Array[String] = []

func _ready() -> void:
	call_deferred("_run")

func _run() -> void:
	print("LIVE PLAYER-PORTAL TRANSITION: boot")
	var game := GAME_SCENE.instantiate() as GameScreen
	assert(game != null, "GameScreen must instantiate")
	add_child(game)
	await get_tree().process_frame
	await get_tree().process_frame
	var session = game.world_session
	assert(session != null and session.world != null, "Initial world session must be ready")

	# Start at the authored Act I origin so every gate below is a real portal
	# spawned by WorldRegionBuilderComponent from regions.json connections.
	var initial_world = session.build_world("castle_royal_gardens", "")
	assert(initial_world != null and session.current_region_id == "castle_royal_gardens")
	await get_tree().process_frame
	await get_tree().physics_frame
	session.region_arrived.connect(func(id: String, _entry: String) -> void: arrival_events.append(id))

	var expected_source := "castle_royal_gardens"
	for target_region in PROGRESSION:
		var source_world: Node2D = session.world
		assert(source_world != null and session.current_region_id == expected_source)
		var player: Player = source_world.get("player") as Player
		assert(player != null and player.interaction_component != null, "Production player interaction must be initialized in " + expected_source)
		var portals: Array = source_world.find_children("*", "RegionPortal", true, false)
		assert(not portals.is_empty(), "World must mount its authored portal nodes")
		var selected: RegionPortal
		for candidate in portals:
			if candidate is RegionPortal and (candidate as RegionPortal).target_region == target_region:
				selected = candidate as RegionPortal
				break
		assert(selected != null, "No runtime-spawned authored portal for %s -> %s (portals=%d)" % [expected_source, target_region, portals.size()])
		assert(selected.connection_id != "" and selected.entry_point != "", "Authored portal route identity/entry missing")
		var target_name := selected.portal_label
		var destination_entry := selected.entry_point
		player.global_position = selected.global_position + Vector2(24.0, 0.0)
		await get_tree().process_frame
		player._scan_for_interactable()
		assert(player.nearby_interactable == selected, "Production player did not select authored portal %s" % selected.connection_id)
		assert(player.current_prompt() == "Travel to " + target_name, "Portal prompt mismatch: " + player.current_prompt())
		print("LIVE PORTAL SELECTED: ", expected_source, " -> ", target_region, " | route=", selected.connection_id)
		player.try_interact()
		await get_tree().process_frame
		await get_tree().physics_frame
		await get_tree().process_frame
		assert(session.current_region_id == target_region, "Portal interaction did not transition session to " + target_region)
		assert(game.current_region_id == target_region, "GameScreen did not follow session transition to " + target_region)
		assert(game.world == session.world and session.world != source_world, "World host did not replace source world")
		assert(session.world.get_parent() == game.world_host and game.world_host.get_child_count() == 1, "World host must contain only destination")
		var destination_player: Node2D = session.world.get("player") as Node2D
		assert(destination_player != null, "Destination player missing in " + target_region)
		var definition: Dictionary = ContentDB.get_region(target_region)
		var entries: Dictionary = definition.get("entry_points", {})
		var entry: Array = entries.get(destination_entry, [])
		assert(entry.size() == 2, "Authored destination entry missing: %s:%s" % [target_region, destination_entry])
		var expected_position := IsoMath.grid_to_world(float(entry[0]), float(entry[1]))
		assert(destination_player.position.distance_to(expected_position) < 2.0, "Destination player did not use authored portal entry in " + target_region)
		assert(arrival_events.size() == PROGRESSION.find(target_region) + 1, "Unexpected arrival signal count: " + str(arrival_events))
		expected_source = target_region
	print("LIVE PLAYER-PORTAL TRANSITION: PASS | actual authored portal chain=", PROGRESSION.size(), " | arrivals=", arrival_events.size())
	game.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame
	# Headless smoke tests bypass normal application shutdown; explicitly stop
	# autoload-owned playback so MP3 streams/playback instances are released.
	AudioDirector.stop_all_audio_immediately()
	await get_tree().create_timer(0.5).timeout
	await get_tree().process_frame
	get_tree().quit(0)




