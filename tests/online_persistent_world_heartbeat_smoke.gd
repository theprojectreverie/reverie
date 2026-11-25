extends SceneTree

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var gateway := root.get_node("MultiplayerGateway")
	assert(gateway.has_method("_process_persistent_world"), "Persistent-world transport loop missing")
	assert(gateway.has_method("persistent_world_last_event_sequence"), "Persistent-world event cursor accessor missing")
	assert(gateway.has_method("is_persistent_world_reconnect_enabled"), "Persistent-world reconnect state accessor missing")
	assert(gateway._build_world_socket_url("ws://127.0.0.1:19089", "server-id") == "ws://127.0.0.1:19089/?serverId=server-id", "Dedicated-server authority-only endpoints must gain the root path before adding serverId")
	assert(gateway._build_world_socket_url("wss://example.test/v1/world/realtime", "server-id") == "wss://example.test/v1/world/realtime?serverId=server-id", "API WebSocket endpoint paths must remain unchanged")
	assert(gateway.has_signal("persistent_world_reconnecting") and gateway.has_signal("persistent_world_recovered"), "Persistent-world recovery lifecycle signals missing")
	assert(gateway.get("_world_reconnect_request") is HTTPRequest, "Persistent-world reconnect ticket request must be initialized")
	var gateway_source := FileAccess.get_file_as_string("res://scripts/online/multiplayer_gateway.gd")
	assert(gateway_source.contains("\"type\":\"ping\",\"lastSequence\":_world_last_event_sequence"), "Persistent-world heartbeat must report its last applied event cursor")
	assert(gateway_source.contains("message_type == \"world_sync_hint\""), "Persistent-world client must request replay when the server detects a missed event")
	assert(gateway_source.contains("/v1/game-servers/") and gateway_source.contains("\"/reconnect\""), "Client must request reconnect tickets through the authenticated game-server reconnect route")
	assert(gateway_source.contains('parsed.get("joinTicket", "")') and gateway_source.contains('parsed.get("endpointUrl", _world_endpoint_url)'), "Client must consume the backend reconnect ticket and endpoint response fields")
	assert(gateway_source.contains('"lastEventSequence":_world_last_event_sequence'), "Reconnect ticket redemption must preserve the last applied durable event cursor")
	assert(gateway_source.contains("WORLD_MAX_RECONNECT_ATTEMPTS := 5") and gateway_source.contains("WORLD_MAX_RECONNECT_DELAY := 15.0"), "Reconnect retries must remain bounded")
	assert(gateway_source.contains("_world_reconnect_request_generation != _world_session_generation") and gateway_source.contains("_world_reconnect_request.cancel_request()"), "Late reconnect responses must be isolated from a newer or intentionally disconnected world session")
	assert(gateway_source.contains("func _handle_session_revoked()") and gateway_source.contains("AuthGateway.invalidate_session(\"session_revoked\")"), "Revoked authentication must invalidate the reconnect session and stop pending ticket requests")
	gateway._world_last_event_sequence = 42
	assert(gateway.persistent_world_last_event_sequence() == 42, "Persistent-world event cursor should expose the last applied sequence")
	gateway._world_sequence_server_id = "server-a"
	gateway._world_last_event_sequence = 42
	assert(gateway.HEARTBEAT_INTERVAL == 15.0, "Persistent-world ping interval should be 15 seconds")
	assert(gateway.HEARTBEAT_TIMEOUT == 45.0, "Persistent-world heartbeat timeout should be 45 seconds")
	var world_disconnect_signals := [0]
	gateway.persistent_world_disconnected.connect(func() -> void: world_disconnect_signals[0] += 1)
	gateway._world_heartbeat_pending = true
	gateway._world_heartbeat_elapsed = 9.0
	gateway._world_heartbeat_wait_elapsed = 12.0
	gateway.disconnect_from_persistent_world()
	assert(not gateway._world_heartbeat_pending, "Disconnect must clear pending world heartbeat")
	assert(is_zero_approx(gateway._world_heartbeat_elapsed), "Disconnect must reset world heartbeat interval")
	assert(world_disconnect_signals[0] == 0, "Resetting an unused world transport must not emit a false disconnect event")
	# Exercise the real reconnect-ticket response handler without depending on a live socket.
	var auth := root.get_node("AuthGateway")
	auth.set("_access_token", "client-reconnect-smoke-token")
	gateway.set("_world_server_id", "5ab5313b-51d3-4a6d-8e6d-bcc602fca15e")
	gateway.set("_world_endpoint_url", "ws://127.0.0.1:19089/v1/world/realtime")
	var reconnect_failures: Array[String] = []
	gateway.set("_world_reconnect_enabled", true)
	gateway.set("_world_reconnect_pending", true)
	gateway.set("_world_reconnect_request_generation", int(gateway.get("_world_session_generation")) - 1)
	gateway._on_world_reconnect_ticket_completed(HTTPRequest.RESULT_SUCCESS, 200, PackedStringArray(), JSON.stringify({"joinTicket":"abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789","endpointUrl":"ws://127.0.0.1:19089/v1/world/realtime"}).to_utf8_buffer())
	assert(gateway.get("_world_peer") == null and gateway.get("_world_reconnect_pending"), "A late response from an older world session must be ignored without clearing the current request")
	gateway.set("_world_reconnect_pending", false)
	gateway.set("_world_reconnect_request_generation", gateway.get("_world_session_generation"))
	gateway.persistent_world_connection_failed.connect(func(reason: String) -> void: reconnect_failures.append(reason))
	gateway.set("_world_reconnect_enabled", true)
	gateway._on_world_reconnect_ticket_completed(HTTPRequest.RESULT_SUCCESS, 404, PackedStringArray(), JSON.stringify({"error":"server_unavailable"}).to_utf8_buffer())
	assert(gateway.is_persistent_world_reconnect_enabled(), "A temporarily unavailable server must remain eligible for bounded reconnect retries")
	gateway.set("_world_reconnect_request_generation", gateway.get("_world_session_generation"))
	gateway._on_world_reconnect_ticket_completed(HTTPRequest.RESULT_SUCCESS, 404, PackedStringArray(), JSON.stringify({"error":"server_assignment_expired"}).to_utf8_buffer())
	assert(not gateway.is_persistent_world_reconnect_enabled(), "Expired world assignment must stop futile reconnect retries")
	assert(not reconnect_failures.is_empty() and reconnect_failures.back().contains("place in this world has expired"), "Expired assignment should explain that the player must rejoin from the world browser")
	gateway.set("_world_reconnect_request_generation", gateway.get("_world_session_generation"))
	gateway.set("_world_reconnect_enabled", true)
	gateway._on_world_reconnect_ticket_completed(HTTPRequest.RESULT_SUCCESS, 200, PackedStringArray(), JSON.stringify({"joinTicket":"abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789","endpointUrl":"ws://127.0.0.1:19089/v1/world/realtime"}).to_utf8_buffer())
	assert(gateway.get("_world_peer") is WebSocketPeer, "A valid reconnect ticket should open a fresh world WebSocket")
	assert(gateway.get("_world_ticket") == "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789", "Fresh reconnect ticket should be held for one-time socket admission")
	assert(not gateway.get("_world_ticket_sent"), "Reconnect ticket should be sent only after the new socket opens")
	gateway.disconnect_from_persistent_world()
	assert(world_disconnect_signals[0] == 1, "Disconnecting an established world session must emit exactly one disconnect event")
	print("[online_persistent_world_heartbeat_smoke] PASS")
	quit()
