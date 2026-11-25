extends SceneTree

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var packed: PackedScene = load("res://scenes/online/dedicated_world_server.tscn")
	assert(packed != null, "Dedicated server scene must load")
	var node: Node = packed.instantiate()
	node.set("transport_test_mode", true)
	node.set("listen_port", 19087)
	node.set("bind_address", "127.0.0.1")
	root.add_child(node)
	assert(node.has_method("_register_server") and node.has_method("_send_heartbeat"), "Registration and heartbeat flows missing")
	assert(node.has_method("_load_world_state") and node.has_method("_save_world_state"), "World persistence flows missing")
	assert(node.has_method("_start_transport") and node.has_method("_poll_listener") and node.has_method("_poll_sessions"), "Dedicated transport handlers missing")
	assert(node.has_method("_snapshot_members") and node.has_method("_redeem_join_ticket"), "Admission and member snapshot handlers missing")
	assert(node.has_method("_handle_peer_message") and node.has_method("_emit_world_event") and node.has_method("_replay_events"), "World message and replay handlers missing")
	assert(node.has_method("_on_durable_replay_completed") and node.has_method("_renew_connection_leases") and node.has_method("_release_connection_lease"), "Durable replay and connection-lease handlers missing")
	assert(node.has_method("_request_player_disconnect") and node.has_method("_on_player_disconnect_completed"), "Lease-aware disconnect lifecycle handlers missing")
	var event_id_a := str(node.call("_make_event_id"))
	var event_id_b := str(node.call("_make_event_id"))
	assert(event_id_a.length() == 36 and event_id_a[14] == "4" and event_id_a[19] == "a" and event_id_a != event_id_b, "Durable event idempotency keys must be unique RFC 4122 UUIDs")
	var source := FileAccess.get_file_as_string("res://scripts/online/dedicated_world_server.gd")
	var packet_read := source.find("var packet := socket.get_packet()")
	var text_check := source.find("if not socket.was_string_packet()", packet_read)
	assert(packet_read >= 0 and text_check > packet_read, "Text packet type must be checked after consuming the packet")
	assert(source.contains("\"type\":\"world_sync_hint\""), "Heartbeat must reconcile client cursors")
	assert(source.contains("/events?after="), "Replay must load from PostgreSQL instead of process-local history")
	assert(source.contains("HTTPClient.METHOD_DELETE, \"{}\""), "Connection lease release must send a valid JSON request body")
	assert(source.contains("HTTPClient.METHOD_PUT, \"{}\""), "Connection lease renewal must send a valid JSON request body")
	assert(source.contains("connectionId"), "Ticket admission must create a durable connection lease")
	node.call("_emit_world_event", {"type":"position","playerId":"smoke-player","x":12.0,"y":8.0})
	assert(int(node.get("_event_sequence")) == 1, "Event sequence must be monotonic")
	var history: Array = node.get("_event_history")
	assert(history.size() == 1 and int(history[0].get("sequence", 0)) == 1, "Sequenced event must be retained")
	node.call("_start_transport")
	var listener: TCPServer = node.get("_tcp_server")
	assert(listener.is_listening(), "Dedicated server must bind a real TCP listener")
	var client := WebSocketPeer.new()
	assert(client.connect_to_url("ws://127.0.0.1:19087") == OK, "WebSocket client must start connecting")
	var opened := false
	var prompted := false
	for i in range(180):
		client.poll()
		if client.get_ready_state() == WebSocketPeer.STATE_OPEN:
			opened = true
		while client.get_available_packet_count() > 0:
			var packet := client.get_packet()
			var parsed: Variant = JSON.parse_string(packet.get_string_from_utf8())
			if typeof(parsed) == TYPE_DICTIONARY and str(parsed.get("type", "")) == "ticket_required":
				prompted = true
		if opened and prompted:
			break
		await process_frame
	assert(opened, "Godot WebSocket handshake with the dedicated TCP listener must succeed")
	assert(prompted, "Dedicated server must issue the join-ticket challenge after handshake")
	client.send_text(JSON.stringify({"type":"join_ticket","ticket":"invalid"}))
	var admission_closed := false
	for i in range(90):
		client.poll()
		admission_closed = client.get_ready_state() == WebSocketPeer.STATE_CLOSED
		if admission_closed:
			break
		await process_frame
	assert(admission_closed, "Dedicated server must close a WebSocket that presents a malformed join ticket")
	client.close()
	listener.stop()
	assert(not listener.is_listening(), "Dedicated listener must close cleanly")
	assert(str(node.get("world_endpoint_url")).begins_with("ws://") or str(node.get("world_endpoint_url")).begins_with("wss://"), "Endpoint URL must use WebSocket transport")
	node.free()
	print("[online_dedicated_server_smoke] PASS — live WebSocket handshake, challenge, and invalid-ticket close")
	quit()
