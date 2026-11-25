extends Node
const GAME_SCENE := preload("res://scenes/game.tscn")
func _ready() -> void:
	print("LIVE TRANSITION TEST: boot")
	_run()
func _probe_player(player: Node2D, label: String) -> void:
	var shape_node := player.get_node("CollisionShape2D") as CollisionShape2D
	var query := PhysicsShapeQueryParameters2D.new()
	query.shape = shape_node.shape
	query.transform = shape_node.global_transform
	query.collision_mask = player.collision_mask
	query.collide_with_bodies = true
	query.collide_with_areas = false
	query.exclude = [player.get_rid()]
	var hits := player.get_world_2d().direct_space_state.intersect_shape(query, 12)
	print("SPAWN COLLISION PROBE ", label, " pos=", player.global_position, " hits=", hits.size())
	assert(hits.is_empty(), "Spawn overlaps a blocking world collider at " + label)
	for hit in hits:
		var collider: Object = hit.get("collider")
		print("  HIT ", collider.get_path() if collider is Node else collider, " class=", collider.get_class() if collider is Object else "unknown")

func _run() -> void:
	print("LIVE TRANSITION TEST: instantiate game")
	var game := GAME_SCENE.instantiate() as GameScreen
	assert(game != null)
	add_child(game)
	await get_tree().process_frame
	print("LIVE TRANSITION TEST: game ready region=", game.current_region_id)
	await get_tree().process_frame
	assert(game.world_session != null and game.world_session.world != null)
	var source_world: Node2D = game.world_session.world
	var source_player: Node2D = source_world.get("player") as Node2D
	assert(source_player != null)
	var arrival_events: Array[String] = []
	game.world_session.region_arrived.connect(func(id: String, _name: String) -> void: arrival_events.append(id))
	print("LIVE TRANSITION TEST: emit portal event")
	EventBus.region_change_requested.emit("royal_gate", "gate_arrival")
	var immediate_player := game.world_session.world.get("player") as Node2D
	_probe_player(immediate_player, "immediate")
	await get_tree().process_frame
	await get_tree().process_frame
	print("LIVE TRANSITION TEST: after event region=", game.current_region_id)
	_probe_player(game.world_session.world.get("player") as Node2D, "after_frames")
	assert(game.world_session.current_region_id == "royal_gate")
	assert(game.current_region_id == "royal_gate")
	assert(game.world == game.world_session.world)
	assert(game.world_session.world != source_world)
	assert(game.world_session.world.get_parent() == game.world_host)
	var destination_player: Node2D = game.world_session.world.get("player") as Node2D
	assert(destination_player != null)
	var entries: Dictionary = ContentDB.get_region("royal_gate").get("entry_points", {})
	var grid: Array = entries.get("gate_arrival", [])
	assert(grid.size() == 2)
	var expected := IsoMath.grid_to_world(float(grid[0]), float(grid[1]))
	print("LIVE SPAWN CHECK: actual=", destination_player.position, " expected=", expected, " distance=", destination_player.position.distance_to(expected))
	assert(destination_player.position.distance_to(expected) < 2.0, "Player spawn drifted from authored entry point")
	assert(arrival_events == ["royal_gate"])
	var children := game.world_host.get_children()
	assert(children.size() == 1 and children[0] == game.world_session.world)
	print("LIVE GAME SCREEN TRANSITION: PASS | garden -> royal_gate via gate_arrival | arrival=", destination_player.position)
	game.queue_free()
	await get_tree().process_frame
	get_tree().quit(0)
