extends SceneTree

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var packed: PackedScene = load("res://scenes/online/dedicated_world_server.tscn")
	var server: Node = packed.instantiate()
	server.set("transport_test_mode", true)
	server.set("bind_address", "127.0.0.1")
	server.set("listen_port", 19087)
	server.set("world_endpoint_url", "ws://127.0.0.1:19087")
	root.add_child(server)
	server.call("_start_transport")
	var peers: Array[WebSocketPeer] = [WebSocketPeer.new(), WebSocketPeer.new(), WebSocketPeer.new()]
	for peer in peers:
		assert(peer.connect_to_url("ws://127.0.0.1:19087") == OK)
	for frame in range(180):
		for peer in peers:
			peer.poll()
		if server.get("_sessions").size() == 3 and peers.all(func(peer): return peer.get_ready_state() == WebSocketPeer.STATE_OPEN):
			break
		await process_frame
	assert(server.get("_sessions").size() == 3)
	# The same per-peer input limit applies to all message types.
	var budget := {}
	for i in 60:
		assert(server.call("_consume_input_budget", budget))
	assert(not server.call("_consume_input_budget", budget))
	budget["input_window_started"] = Time.get_ticks_msec() - 1001
	assert(server.call("_consume_input_budget", budget))
	# Real connection: oversized input closes that socket before parsing.
	peers[0].send_text("x".repeat(4097))
	for frame in range(180):
		for peer in peers:
			peer.poll()
		if peers[0].get_ready_state() == WebSocketPeer.STATE_CLOSED:
			break
		await process_frame
	assert(peers[0].get_close_code() == 1009)
	assert(peers[0].get_close_reason() == "message_too_large")
	assert(peers[1].get_ready_state() == WebSocketPeer.STATE_OPEN)
	for frame in range(10):
		await process_frame
	# A tiny test-only output budget exercises the same production guard.
	var sessions: Dictionary = server.get("_sessions")
	var ids: Array = sessions.keys()
	assert(ids.size() == 2)
	server.set("_outbound_budget_bytes", 64)
	var closing_socket: WebSocketPeer = sessions[ids[0]]["socket"]
	server.call("_send_encoded", int(ids[0]), "x".repeat(65).to_utf8_buffer())
	assert(closing_socket.get_ready_state() != WebSocketPeer.STATE_OPEN)
	closing_socket = null
	for frame in range(180):
		for peer in peers:
			peer.poll()
		if peers[1].get_ready_state() == WebSocketPeer.STATE_CLOSED or peers[2].get_ready_state() == WebSocketPeer.STATE_CLOSED:
			break
		await process_frame
	var slow: WebSocketPeer = peers[1] if peers[1].get_ready_state() == WebSocketPeer.STATE_CLOSED else peers[2]
	var healthy: WebSocketPeer = peers[2] if slow == peers[1] else peers[1]
	assert(slow.get_ready_state() == WebSocketPeer.STATE_CLOSED)
	assert(healthy.get_ready_state() == WebSocketPeer.STATE_OPEN)
	for frame in range(10):
		await process_frame
	# Saturate a tiny test queue without making any backend requests.
	server.set("transport_test_mode", false)
	server.set("_event_queue_budget", 2)
	var queued: Array[Dictionary] = [
		{"event_id":"one","payload":{"playerId":"fixture","type":"position","x":1,"y":1}},
		{"event_id":"two","payload":{"playerId":"fixture","type":"position","x":2,"y":2}}
	]
	server.set("_event_queue", queued)
	assert(server.call("_persistence_busy"))
	sessions = server.get("_sessions")
	ids = sessions.keys()
	assert(ids.size() == 1)
	var session: Dictionary = sessions[ids[0]]
	session["authenticated"] = true
	session["player_id"] = "fixture"
	var saturated_socket: WebSocketPeer = session["socket"]
	session["last_position_at"] = Time.get_ticks_msec() - 200
	server.call("_handle_peer_message", int(ids[0]), {"type":"position","x":100,"y":100})
	assert(saturated_socket.get_ready_state() == WebSocketPeer.STATE_OPEN)
	assert(server.get("_event_queue").size() == 2)
	assert(server.get("_player_positions").is_empty())
	assert(server.get("_deferred_positions").size() == 1)
	session["last_position_at"] = Time.get_ticks_msec() - 200
	server.call("_handle_peer_message", int(ids[0]), {"type":"position","x":110,"y":110})
	assert(server.get("_deferred_positions").size() == 1)
	assert(server.get("_coalesced_positions") == 1)
	assert(server.get("_event_queue")[0]["event_id"] == "one")
	assert(server.get("_event_queue")[1]["event_id"] == "two")
	server.set("_event_queue", [] as Array[Dictionary])
	server.call("_flush_deferred_positions")
	assert(server.get("_deferred_positions").is_empty())
	assert(server.get("_player_positions")["fixture"] == Vector2(110,110))
	assert(server.get("_event_queue").size() == 1)
	assert(saturated_socket.get_ready_state() == WebSocketPeer.STATE_OPEN)
	server.set("_event_queue", [] as Array[Dictionary])
	assert(not server.call("_persistence_busy"))
	saturated_socket = null
	session = {}
	server.set("transport_test_mode", true)
	server.queue_free()
	await process_frame
	print("SERVER_BACKPRESSURE_SMOKE_PASS input_limit=true oversized=true outbound_guard=true queue_bound=true latest_proposal=true healthy_peer_retained=true")
	quit()
