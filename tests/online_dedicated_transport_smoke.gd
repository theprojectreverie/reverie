extends SceneTree

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var packed: PackedScene = load("res://scenes/online/dedicated_world_server.tscn")
	assert(packed != null, "Dedicated server scene must load")
	var server: Node = packed.instantiate()
	server.set("transport_test_mode", true)
	server.set("bind_address", "127.0.0.1")
	server.set("listen_port", 19083)
	server.set("world_endpoint_url", "ws://127.0.0.1:19083")
	root.add_child(server)
	server.set("_operation", "heartbeat")
	server.call("_start_transport")
	assert(bool(server.get("_ready_for_heartbeat")), "Transport should become ready")

	var clients: Array[WebSocketPeer] = [WebSocketPeer.new(), WebSocketPeer.new()]
	for client in clients:
		var connect_error := client.connect_to_url("ws://127.0.0.1:19083")
		assert(connect_error == OK, "Independent WebSocket clients should begin connecting")

	var prompts := [false, false]
	for frame in range(240):
		for index in range(clients.size()):
			var client: WebSocketPeer = clients[index]
			client.poll()
			if client.get_ready_state() == WebSocketPeer.STATE_OPEN:
				while client.get_available_packet_count() > 0:
					var packet: Variant = JSON.parse_string(client.get_packet().get_string_from_utf8())
					if typeof(packet) == TYPE_DICTIONARY and packet.get("type", "") == "ticket_required":
						prompts[index] = true
		if prompts[0] and prompts[1]:
			break
		await process_frame

	assert(prompts[0] and prompts[1], "Both independent clients must receive admission prompts")
	assert(server.get("_sessions").size() == 2, "Dedicated listener must track two simultaneous sessions")
	clients[0].send_text(JSON.stringify({"type":"position","x":500.0,"y":500.0}))
	for frame in range(60):
		clients[0].poll()
		if clients[0].get_ready_state() == WebSocketPeer.STATE_CLOSED:
			break
		await process_frame
	assert(clients[0].get_ready_state() == WebSocketPeer.STATE_CLOSED, "Unauthenticated client must be closed when it attempts a world-state update")
	assert((server.get("_player_positions") as Dictionary).is_empty(), "Unauthenticated client must not mutate authoritative positions")
	for frame in range(30):
		if server.get("_sessions").size() == 1:
			break
		await process_frame
	assert(server.get("_sessions").size() == 1, "Rejected unauthenticated session must be removed")
	server.set("_sessions", {99:{"authenticated":true,"player_id":"test-player"}})
	server.set("_player_profiles", {"test-player":{"name":"Raven","level":17}})
	var member_snapshot: Array = server.call("_snapshot_members", "test-player")
	assert(member_snapshot.size() == 1, "Member snapshot should include authenticated peers")
	assert(member_snapshot[0].get("name", "") == "Raven" and member_snapshot[0].get("level", 0) == 17, "Member snapshot must preserve authoritative profile metadata")
	server.set("_disconnect_timers", {"grace-player":true})
	server.set("_player_profiles", {"test-player":{"name":"Raven","level":17},"grace-player":{"name":"Mira","level":22}})
	server.set("_player_positions", {"grace-player":Vector2(42.0,84.0)})
	var grace_snapshot: Array = server.call("_snapshot_members", "test-player")
	var grace_member: Dictionary = {}
	for member in grace_snapshot:
		if str(member.get("playerId","")) == "grace-player":
			grace_member = member
	assert(grace_snapshot.size() == 2 and grace_member.get("name","") == "Mira" and grace_member.get("x",-1.0) == 42.0 and grace_member.get("y",-1.0) == 84.0, "Snapshots must retain disconnected party members and their last authoritative positions during reconnect grace")
	server.set("_disconnect_timers", {})
	server.set("_sessions", {})
	print("[online_dedicated_transport_smoke] PASS — two live clients, admission enforcement, profile snapshot")

	for client in clients:
		client.close()
	for frame in range(5):
		for client in clients:
			client.poll()
		await process_frame
	server.queue_free()
	await process_frame
	quit()
