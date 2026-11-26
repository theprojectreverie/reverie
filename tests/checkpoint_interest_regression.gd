extends Node

func _ready() -> void:
	call_deferred("_run")

func _run() -> void:
	var script: Script = load("res://scripts/online/dedicated_world_server.gd")
	var server: Node = script.new()
	server.transport_test_mode = true
	get_tree().root.add_child(server)
	await get_tree().process_frame
	var player_id := "checkpoint-player"
	server._player_positions = {player_id: Vector2(8020.0, 30.0)}
	server._committed_interest_positions = {player_id: Vector2(8020.0, 30.0)}
	var entries: Array[Dictionary] = [{
		"payload": {"type": "position", "playerId": player_id, "x": 7970.0, "y": 30.0, "sequence": 1},
		"except_peer_id": -1
	}]
	server._publish_committed_events(entries)
	assert(server._committed_interest_positions[player_id] == Vector2(8020.0, 30.0))
	print("CHECKPOINT_INTEREST_REGRESSION_PASS: stale durable checkpoint cannot overwrite newer transient spatial position")
	server.queue_free()
	await get_tree().process_frame
	get_tree().quit()
