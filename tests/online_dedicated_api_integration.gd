extends SceneTree

const API := "http://127.0.0.1:8787"
const PASSWORD := "Reverie-E2E-Local-2026!"

func _initialize() -> void:
	call_deferred("_run")

func _request_json(url: String, method: int, headers: PackedStringArray = PackedStringArray(), body: Dictionary = {}) -> Dictionary:
	var request := HTTPRequest.new()
	request.timeout = 12.0
	root.add_child(request)
	var payload := JSON.stringify(body)
	var error := request.request(url, headers, method, payload)
	assert(error == OK, "Could not start HTTP request: " + url)
	var response: Array = await request.request_completed
	request.queue_free()
	var parsed: Variant = JSON.parse_string(response[3].get_string_from_utf8())
	return {"result":response[0],"code":response[1],"body":parsed}

func _create_player(suffix: String, name: String) -> Dictionary:
	var email := "reverie-e2e-" + suffix + "@example.test"
	var registered := await _request_json(API + "/v1/auth/register", HTTPClient.METHOD_POST, PackedStringArray(["Content-Type: application/json"]), {"email":email,"password":PASSWORD,"playerName":name})
	assert(registered.code == 201, "Test account registration failed: " + str(registered.body))
	var verification_token := str(registered.body.get("developmentVerificationToken", ""))
	assert(verification_token.length() >= 32, "Development verification token missing")
	var verified := await _request_json(API + "/v1/auth/verify-email", HTTPClient.METHOD_POST, PackedStringArray(["Content-Type: application/json"]), {"token":verification_token})
	assert(verified.code == 200, "Test account verification failed")
	var logged_in := await _request_json(API + "/v1/auth/login", HTTPClient.METHOD_POST, PackedStringArray(["Content-Type: application/json"]), {"email":email,"password":PASSWORD})
	assert(logged_in.code == 200, "Test account login failed: " + str(logged_in.body))
	return {"email":email,"player_id":str(logged_in.body.player.id),"name":name,"token":str(logged_in.body.accessToken)}

func _connect_with_ticket(endpoint: String, ticket: String) -> WebSocketPeer:
	var socket := WebSocketPeer.new()
	assert(socket.connect_to_url(endpoint) == OK, "WebSocket connect request failed")
	var sent_ticket := false
	for frame in range(180):
		socket.poll()
		if socket.get_ready_state() == WebSocketPeer.STATE_OPEN and not sent_ticket:
			socket.send_text(JSON.stringify({"type":"join_ticket","ticket":ticket}))
			sent_ticket = true
		if socket.get_ready_state() == WebSocketPeer.STATE_CLOSED:
			break
		await process_frame
	assert(sent_ticket and socket.get_ready_state() == WebSocketPeer.STATE_OPEN, "WebSocket did not open for ticket redemption")
	return socket

func _wait_world_joined(socket: WebSocketPeer, expected_player_id: String) -> Dictionary:
	for frame in range(240):
		socket.poll()
		while socket.get_available_packet_count() > 0:
			var packet: Variant = JSON.parse_string(socket.get_packet().get_string_from_utf8())
			if typeof(packet) == TYPE_DICTIONARY and packet.get("type", "") == "world_joined" and packet.get("playerId", "") == expected_player_id:
				return packet
		await process_frame
	assert(false, "Timed out waiting for authenticated world_joined")
	return {}

func _run() -> void:
	var timestamp := str(int(Time.get_unix_time_from_system()))
	var server: Node = load("res://scenes/online/dedicated_world_server.tscn").instantiate()
	server.set("server_key", "reverie-e2e-" + timestamp)
	server.set("display_name", "E2E Test Server")
	server.set("region_id", "castle_royal_gardens")
	server.set("world_endpoint_url", "ws://127.0.0.1:19112")
	server.set("bind_address", "127.0.0.1")
	server.set("listen_port", 19112)
	server.set("heartbeat_interval", 20.0)
	root.add_child(server)

	for frame in range(600):
		if bool(server.get("_ready_for_heartbeat")) and not str(server.get("_server_id")).is_empty():
			break
		await process_frame
	assert(bool(server.get("_ready_for_heartbeat")), "Dedicated server did not register and start its transport")
	for frame in range(180):
		if str(server.get("_operation")).is_empty():
			break
		await process_frame
	await create_timer(0.25).timeout

	var player_a := await _create_player(timestamp + "a", "E2E_Raven_" + timestamp.substr(timestamp.length() - 5))
	var player_b := await _create_player(timestamp + "b", "E2E_Mira_" + timestamp.substr(timestamp.length() - 5))
	var server_id := str(server.get("_server_id"))
	var auth_a := PackedStringArray(["Authorization: Bearer " + player_a.token, "Content-Type: application/json"])
	var auth_b := PackedStringArray(["Authorization: Bearer " + player_b.token, "Content-Type: application/json"])
	var join_a := await _request_json(API + "/v1/game-servers/" + server_id + "/join", HTTPClient.METHOD_POST, auth_a, {})
	var join_b := await _request_json(API + "/v1/game-servers/" + server_id + "/join", HTTPClient.METHOD_POST, auth_b, {})
	assert(join_a.code == 200 and join_b.code == 200, "API join-ticket issuance failed: A=" + str(join_a.code) + " " + str(join_a.body) + " B=" + str(join_b.code) + " " + str(join_b.body))
	var endpoint := str(join_a.body.endpointUrl)
	assert(endpoint == "ws://127.0.0.1:19112", "API directory endpoint did not match the dedicated listener")

	var socket_a := await _connect_with_ticket(endpoint, str(join_a.body.joinTicket))
	var joined_a := await _wait_world_joined(socket_a, player_a.player_id)
	assert(joined_a.get("playerId", "") == player_a.player_id, "First player identity mismatch")

	var socket_b := await _connect_with_ticket(endpoint, str(join_b.body.joinTicket))
	var joined_b := await _wait_world_joined(socket_b, player_b.player_id)
	var members: Array = joined_b.get("members", [])
	var found_a := false
	for member in members:
		if member.get("playerId", "") == player_a.player_id and member.get("name", "") == player_a.name:
			found_a = true
	assert(found_a, "Second player's snapshot must contain the first player's real profile")

	var replay := await _request_json(API + "/v1/game-servers/" + server_id + "/consume-ticket", HTTPClient.METHOD_POST, PackedStringArray(["Authorization: Bearer " + str(server.get("_server_token")), "Content-Type: application/json"]), {"ticket":str(join_a.body.joinTicket)})
	assert(replay.code == 401, "Redeemed join ticket must not be reusable")

	await create_timer(0.2).timeout
	socket_b.send_text(JSON.stringify({"type":"position","x":12.0,"y":8.0}))
	var movement_seen := false
	for frame in range(180):
		socket_a.poll()
		while socket_a.get_available_packet_count() > 0:
			var event: Variant = JSON.parse_string(socket_a.get_packet().get_string_from_utf8())
			if typeof(event) == TYPE_DICTIONARY and event.get("type", "") == "position" and event.get("playerId", "") == player_b.player_id and is_equal_approx(float(event.get("x", 0.0)), 12.0):
				movement_seen = true
		if movement_seen:
			break
		await process_frame
	assert(movement_seen, "Position update from player B must reach player A")

	socket_a.close()
	for frame in range(8):
		socket_a.poll()
		await process_frame
	var reconnect := await _request_json(API + "/v1/game-servers/" + server_id + "/reconnect", HTTPClient.METHOD_POST, auth_a, {})
	assert(reconnect.code == 200, "Reconnect ticket issuance failed")
	var socket_a_reconnected := await _connect_with_ticket(endpoint, str(reconnect.body.joinTicket))
	var joined_again := await _wait_world_joined(socket_a_reconnected, player_a.player_id)
	assert(joined_again.get("playerId", "") == player_a.player_id, "Reconnected player identity mismatch")

	socket_a_reconnected.close()
	socket_b.close()
	for frame in range(8):
		socket_a_reconnected.poll()
		socket_b.poll()
		await process_frame
	await _request_json(API + "/v1/game-servers/" + server_id + "/leave", HTTPClient.METHOD_POST, auth_a, {})
	await _request_json(API + "/v1/game-servers/" + server_id + "/leave", HTTPClient.METHOD_POST, auth_b, {})

	for frame in range(240):
		if str(server.get("_operation")).is_empty():
			break
		await process_frame
	server.call("_send_final_save_and_offline")
	if not str(server.get("_operation")).is_empty():
		await server.get("_http").request_completed
	server.queue_free()
	await process_frame
	print("[online_dedicated_api_integration] PASS — API registration, two authenticated players, ticket redemption, single-use replay rejection, real profile snapshot, movement broadcast, reconnect")
	quit()
