extends Node
## Authenticated realtime transport with bounded reconnect and replay support.
signal lobby_connected(lobby_id: String)
signal lobby_disconnected
signal connection_failed(reason: String)
signal server_event(payload: Dictionary)
signal persistent_world_connected(server_id: String)
signal persistent_world_disconnected
signal persistent_world_event(payload: Dictionary)
signal persistent_world_connection_failed(reason: String)
signal persistent_world_reconnecting(attempt: int, max_attempts: int)
signal persistent_world_recovered(server_id: String)

@export var websocket_url := "ws://127.0.0.1:8787/v1/realtime"
@export var persistent_world_websocket_url := "ws://127.0.0.1:8787/v1/world/realtime"
const MAX_RECONNECT_ATTEMPTS := 5
const MAX_RECONNECT_DELAY := 15.0
const HEARTBEAT_INTERVAL := 15.0
const HEARTBEAT_TIMEOUT := 45.0
const WORLD_MAX_RECONNECT_ATTEMPTS := 5
const WORLD_MAX_RECONNECT_DELAY := 15.0
const WORLD_CONNECT_TIMEOUT := 12.0

var _peer: WebSocketPeer
var _lobby_id := ""
var standalone_expedition_id := ""
var standalone_expedition_region := ""
var _party_travel_pending := false
var _connection_pending := false
var _connected_emitted := false
var _reconnect_enabled := false
var _reconnect_elapsed := 0.0
var _reconnect_attempts := 0
var _heartbeat_elapsed := 0.0
var _heartbeat_wait_elapsed := 0.0
var _heartbeat_pending := false
var _world_peer: WebSocketPeer
var _world_server_id := ""
var _world_ticket := ""
var _world_ticket_sent := false
var _world_ready := false
var _world_interest_windows := false
var _world_heartbeat_elapsed := 0.0
var _world_heartbeat_wait_elapsed := 0.0
var _world_heartbeat_pending := false
var _world_connect_elapsed := 0.0
var _world_last_event_sequence := 0
var _world_sequence_server_id := ""
var _world_replay_requested := false
var _world_endpoint_url := ""
var _world_reconnect_enabled := false
var _world_reconnect_elapsed := 0.0
var _world_reconnect_attempts := 0
var _world_reconnect_delay := 1.0
var _world_reconnect_pending := false
var _world_session_generation := 0
var _world_reconnect_request_generation := -1
var _world_reconnect_request: HTTPRequest

func _ready() -> void:
	if preload("res://scripts/online/connection_profile.gd").is_public_alpha():
		websocket_url=preload("res://scripts/online/connection_profile.gd").realtime_url(true)
		persistent_world_websocket_url=preload("res://scripts/online/connection_profile.gd").persistent_world_url(true)
	_world_reconnect_request = HTTPRequest.new()
	_world_reconnect_request.name = "WorldReconnectTicketRequest"
	_world_reconnect_request.timeout = 12.0
	add_child(_world_reconnect_request)
	_world_reconnect_request.request_completed.connect(_on_world_reconnect_ticket_completed)

func is_lobby_reconnect_enabled() -> bool:
	return _reconnect_enabled and not _lobby_id.is_empty()

func _build_world_socket_url(endpoint: String, server_id: String) -> String:
	# API-hosted endpoints already provide a path; dedicated endpoints may not.
	var socket_url: String = endpoint
	var scheme_end: int = socket_url.find("://")
	var path_start: int = -1
	if scheme_end >= 0:
		path_start = socket_url.find("/", scheme_end + 3)
	if path_start < 0:
		socket_url += "/"
	return socket_url + "?serverId=" + server_id.uri_encode()

func persistent_world_last_event_sequence() -> int:
	return _world_last_event_sequence

func is_persistent_world_reconnect_enabled() -> bool:
	return _world_reconnect_enabled and not _world_server_id.is_empty()

func connect_to_persistent_world(server_id: String, join_ticket: String, endpoint_url: String = "") -> Error:
	if not preload("res://scripts/online/connection_profile.gd").persistent_world_enabled(preload("res://scripts/online/connection_profile.gd").is_public_alpha()):
		return ERR_UNAVAILABLE
	if not AuthGateway.is_authenticated():
		return ERR_UNAUTHORIZED
	if not _is_uuid(server_id) or join_ticket.length() < 40 or join_ticket.length() > 200:
		return ERR_INVALID_PARAMETER
	var target_url := endpoint_url.strip_edges() if not endpoint_url.strip_edges().is_empty() else persistent_world_websocket_url
	if not (target_url.begins_with("wss://") or target_url.begins_with("ws://")) or target_url.contains("#") or target_url.contains("?"):
		return ERR_INVALID_PARAMETER
	# Do not tear down a healthy world session or arm reconnect state while
	# authentication is still refreshing. The caller can safely retry on ERR_BUSY.
	if not AuthGateway.access_token_ready_for_connection():
		return ERR_BUSY
	if _world_sequence_server_id != server_id:
		_world_last_event_sequence = 0
		_world_sequence_server_id = server_id
	disconnect_from_persistent_world()
	_world_reconnect_enabled = true
	_world_reconnect_elapsed = 0.0
	_world_reconnect_attempts = 0
	_world_reconnect_delay = 1.0
	_world_reconnect_pending = false
	_world_endpoint_url = target_url
	_world_server_id = server_id
	_world_ticket = join_ticket
	_world_ticket_sent = false
	_world_ready = false
	_world_heartbeat_elapsed = 0.0
	_world_heartbeat_wait_elapsed = 0.0
	_world_heartbeat_pending = false
	_world_peer = WebSocketPeer.new()
	_world_connect_elapsed = 0.0
	_world_peer.handshake_headers = PackedStringArray(["Authorization: Bearer " + AuthGateway.access_token_for_request()])
	var url := _build_world_socket_url(target_url, server_id)
	var result := _world_peer.connect_to_url(url)
	if result != OK:
		_world_peer = null
		_world_server_id = ""
		_world_ticket = ""
		persistent_world_connection_failed.emit("Could not start the persistent-world connection.")
	return result

func disconnect_from_persistent_world() -> void:
	var had_persistent_world_session := _world_peer != null or not _world_server_id.is_empty() or not _world_ticket.is_empty()
	_world_session_generation += 1
	_world_reconnect_request_generation = -1
	if _world_reconnect_pending and _world_reconnect_request != null:
		_world_reconnect_request.cancel_request()
	_world_reconnect_pending = false
	_world_connect_elapsed = 0.0
	_world_reconnect_enabled = false
	_world_reconnect_elapsed = 0.0
	_world_reconnect_attempts = 0
	_world_reconnect_delay = 1.0
	if _world_peer != null:
		_world_peer.close()
	_world_peer = null
	_world_server_id = ""
	_world_ticket = ""
	_world_ticket_sent = false
	_world_ready = false
	_world_heartbeat_elapsed = 0.0
	_world_heartbeat_wait_elapsed = 0.0
	_world_heartbeat_pending = false
	if had_persistent_world_session:
		persistent_world_disconnected.emit()

func is_connected_to_persistent_world() -> bool:
	return _world_peer != null and _world_peer.get_ready_state() == WebSocketPeer.STATE_OPEN and _world_ready

func send_world_position(world_position: Vector2) -> Error:
	return _send_world({"type":"position","x":world_position.x,"y":world_position.y})

func send_world_emote(emote_id: String) -> Error:
	if emote_id not in ["wave","cheer","sad","dance"]:
		return ERR_INVALID_PARAMETER
	return _send_world({"type":"emote","emoteId":emote_id})

func _send_world(payload: Dictionary) -> Error:
	if not is_connected_to_persistent_world():
		return ERR_UNAVAILABLE
	return _world_peer.send_text(JSON.stringify(payload))

func connect_to_lobby(lobby_id: String) -> Error:
	if not AuthGateway.is_authenticated():
		return ERR_UNAUTHORIZED
	if _peer != null and _peer.get_ready_state() != WebSocketPeer.STATE_CLOSED:
		_peer.close()
	_lobby_id = lobby_id
	_reconnect_enabled = true
	_reconnect_elapsed = 0.0
	_reconnect_attempts = 0
	return _begin_connection()

func _begin_connection() -> Error:
	if not AuthGateway.is_authenticated():
		_reconnect_enabled = false
		connection_failed.emit("Your sign-in session expired. Sign in again.")
		return ERR_UNAUTHORIZED
	if not AuthGateway.access_token_ready_for_connection():
		return ERR_BUSY
	_peer = WebSocketPeer.new()
	_connection_pending = true
	_connected_emitted = false
	_reset_heartbeat()
	var url := websocket_url + "?lobbyId=" + _lobby_id.uri_encode()
	_peer.handshake_headers = PackedStringArray(["Authorization: Bearer " + AuthGateway.access_token_for_request()])
	var result := _peer.connect_to_url(url)
	if result != OK:
		_connection_pending = false
		_peer = null
		connection_failed.emit("Could not start the multiplayer connection.")
	return result

func disconnect_from_lobby() -> void:
	standalone_expedition_id = ""
	standalone_expedition_region = ""
	_reconnect_enabled = false
	_reconnect_elapsed = 0.0
	_reconnect_attempts = 0
	if _peer != null:
		_peer.close()
	_peer = null
	_lobby_id = ""
	_connection_pending = false
	_connected_emitted = false
	_reset_heartbeat()
	lobby_disconnected.emit()

func is_connected_to_lobby() -> bool:
	return _peer != null and _peer.get_ready_state() == WebSocketPeer.STATE_OPEN

func request_expedition_travel(destination_scene: String) -> Error:
	if standalone_expedition_id.is_empty() or _party_travel_pending:
		return ERR_UNAVAILABLE
	var data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://resources/data/six_zone_expeditions.json"))
	if not data.has(standalone_expedition_region):
		return ERR_INVALID_PARAMETER
	for id in data[standalone_expedition_region]["portals"]:
		if str(data[id]["scene"]) == destination_scene:
			return _send({"type":"region_transition","regionId":id})
	return ERR_INVALID_PARAMETER

func _route_expedition_event(event: Dictionary) -> bool:
	if standalone_expedition_id.is_empty() or standalone_expedition_id != _lobby_id:
		return false
	var target := ""
	if str(event.get("type", "")) == "region_transition":
		target = str(event.get("regionId", ""))
	elif str(event.get("type", "")) == "snapshot":
		var members: Array = event.get("members", [])
		if not members.is_empty() and members[0] is Dictionary:
			target = str(members[0].get("region_id", ""))
	if target.is_empty() or target == standalone_expedition_region:
		return _party_travel_pending
	var data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://resources/data/six_zone_expeditions.json"))
	if not data.has(target):
		return false
	if not _party_travel_pending:
		_party_travel_pending = true
		var player = get_tree().get_first_node_in_group("player")
		if player != null and player.has_method("set_network_recovery_paused"):
			player.set_network_recovery_paused(true)
		call_deferred("_apply_expedition_travel", target, str(data[target]["scene"]))
	return true

func _apply_expedition_travel(region: String, scene_path: String) -> void:
	if standalone_expedition_id.is_empty():
		_party_travel_pending = false
		return
	standalone_expedition_region = region
	var result := get_tree().change_scene_to_file(scene_path)
	_party_travel_pending = false
	if result != OK:
		connection_failed.emit("Could not load the expedition destination.")

func request_exploration_objective(objective_id: String) -> Error:
	if standalone_expedition_id.is_empty() or _party_travel_pending or standalone_expedition_region not in ["six_zone_willow_fields", "six_zone_elderwood_grove", "six_zone_forsaken_ruins"]:
		return ERR_UNAVAILABLE
	return _send({"type":"exploration_objective", "objectiveId":objective_id})

func request_monster_attack(monster_id: String, guard: bool = false) -> Error:
	if standalone_expedition_region not in ["six_zone_royal_gardens", "six_zone_royal_gate", "six_zone_willow_fields", "six_zone_forsaken_ruins", "six_zone_ruined_tower"]:
		return ERR_UNAVAILABLE
	return _send({"type":"monster_attack","monsterId":monster_id,"guard":guard})

func send_position(world_position: Vector2, region_id: String) -> Error:
	if region_id.is_empty():
		return ERR_INVALID_PARAMETER
	return _send({"type":"position","regionId":region_id,"x":world_position.x,"y":world_position.y})

func send_emote(emote_id: String) -> Error:
	if emote_id not in ["wave","cheer","sad","dance"]:
		return ERR_INVALID_PARAMETER
	return _send({"type":"emote","emoteId":emote_id})

func acknowledge_sequence(sequence: int) -> Error:
	return _send({"type":"ack","sequence":sequence})

func resume_from_sequence(sequence: int) -> Error:
	return _send({"type":"resume","lastSequence":sequence})

func ping_server() -> Error:
	return _send({"type":"ping"})

func _send(payload: Dictionary) -> Error:
	if not is_connected_to_lobby():
		return ERR_UNAVAILABLE
	return _peer.send_text(JSON.stringify(payload))

func _process(delta: float) -> void:
	_process_persistent_world(delta)
	if _peer == null:
		if _reconnect_enabled and not _lobby_id.is_empty() and not _connection_pending:
			if not AuthGateway.is_authenticated():
				_begin_connection()
				return
			if not AuthGateway.access_token_ready_for_connection():
				return
			_reconnect_elapsed += delta
			var wait_seconds := minf(pow(2.0, float(_reconnect_attempts)), MAX_RECONNECT_DELAY)
			if _reconnect_elapsed >= wait_seconds:
				if _reconnect_attempts >= MAX_RECONNECT_ATTEMPTS:
					_reconnect_enabled = false
					connection_failed.emit("Could not restore the shared world after several attempts.")
				else:
					_reconnect_attempts += 1
					_reconnect_elapsed = 0.0
					_begin_connection()
		return
	_peer.poll()
	var state := _peer.get_ready_state()
	if state == WebSocketPeer.STATE_OPEN:
		if not _connected_emitted:
			_connected_emitted = true
			_connection_pending = false
			_reconnect_attempts = 0
			_reconnect_elapsed = 0.0
			_reset_heartbeat()
			lobby_connected.emit(_lobby_id)
		if _heartbeat_pending:
			_heartbeat_wait_elapsed += delta
			if _heartbeat_wait_elapsed >= HEARTBEAT_TIMEOUT:
				_peer.close(1001, "heartbeat_timeout")
				return
		else:
			_heartbeat_elapsed += delta
			if _heartbeat_elapsed >= HEARTBEAT_INTERVAL:
				var ping_result := _peer.send_text(JSON.stringify({"type":"ping"}))
				if ping_result != OK:
					_peer.close(1001, "heartbeat_send_failed")
					return
				_heartbeat_pending = true
				_heartbeat_wait_elapsed = 0.0
				_heartbeat_elapsed = 0.0
		while _peer.get_available_packet_count() > 0:
			var packet := _peer.get_packet()
			var parsed: Variant = JSON.parse_string(packet.get_string_from_utf8())
			if typeof(parsed) == TYPE_DICTIONARY:
				if str(parsed.get("type", "")) == "pong":
					_heartbeat_pending = false
					_heartbeat_wait_elapsed = 0.0
					_heartbeat_elapsed = 0.0
				elif str(parsed.get("type", "")) == "rejected" and str(parsed.get("reason", "")) == "session_revoked":
					_handle_session_revoked()
					break
				else:
					if str(parsed.get("type", "")) == "rejected" and not standalone_expedition_id.is_empty():
						match str(parsed.get("reason", "")):
							"leader_or_region_required":
								EventBus.toast_requested.emit("Only the party leader can move the expedition through a portal.")
							"portal_proximity_required":
								EventBus.toast_requested.emit("Move closer to the portal and try again.")
							"invalid_region_transition":
								EventBus.toast_requested.emit("This expedition cannot travel directly to that zone.")
					if not _route_expedition_event(parsed):
						server_event.emit(parsed)
	elif state == WebSocketPeer.STATE_CLOSED:
		var reason := _peer.get_close_reason()
		if _connection_pending:
			_connection_pending = false
			connection_failed.emit(reason if not reason.is_empty() else "The multiplayer server rejected the connection.")
		elif _connected_emitted:
			_connected_emitted = false
			lobby_disconnected.emit()
			connection_failed.emit(reason if not reason.is_empty() else "The shared-world connection was interrupted.")
		_peer = null
		_reset_heartbeat()

func _on_world_reconnect_ticket_completed(result: int, response_code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
	# A cancelled request from an earlier world session must never mutate the new one.
	if _world_reconnect_request_generation != _world_session_generation:
		return
	_world_reconnect_pending = false
	_world_reconnect_request_generation = -1
	if not _world_reconnect_enabled:
		return
	var parsed: Variant = JSON.parse_string(body.get_string_from_utf8())
	if result != HTTPRequest.RESULT_SUCCESS:
		_world_reconnect_elapsed = 0.0
		return
	if response_code == 401 or response_code == 403:
		_world_reconnect_enabled = false
		persistent_world_connection_failed.emit("Your sign-in session expired. Sign in again.")
		return
	if typeof(parsed) == TYPE_DICTIONARY:
		var reconnect_error := str(parsed.get("error", ""))
		if response_code == 404 and reconnect_error == "server_assignment_expired":
			_world_reconnect_enabled = false
			persistent_world_connection_failed.emit("Your place in this world has expired. Return to the world browser to join again.")
			return
	if response_code != 200 or typeof(parsed) != TYPE_DICTIONARY:
		# Server unavailable, rate-limited, and transient backend failures remain retryable.
		_world_reconnect_elapsed = 0.0
		return
	var ticket := str(parsed.get("joinTicket", ""))
	var endpoint := str(parsed.get("endpointUrl", _world_endpoint_url))
	if ticket.length() < 40 or ticket.length() > 200:
		_world_reconnect_elapsed = 0.0
		return
	if (not endpoint.begins_with("ws://") and not endpoint.begins_with("wss://")) or endpoint.contains("?") or endpoint.contains("#"):
		_world_reconnect_elapsed = 0.0
		return
	_world_endpoint_url = endpoint
	_world_ticket = ticket
	_world_ticket_sent = false
	_world_ready = false
	_world_heartbeat_elapsed = 0.0
	_world_heartbeat_wait_elapsed = 0.0
	_world_heartbeat_pending = false
	_world_peer = WebSocketPeer.new()
	_world_connect_elapsed = 0.0
	_world_peer.handshake_headers = PackedStringArray(["Authorization: Bearer " + AuthGateway.access_token_for_request()])
	var connect_error := _world_peer.connect_to_url(_build_world_socket_url(_world_endpoint_url, _world_server_id))
	if connect_error != OK:
		_world_peer = null
		_world_reconnect_elapsed = 0.0

func _process_persistent_world(delta: float) -> void:
	if _world_peer == null:
		if _world_reconnect_enabled and not _world_server_id.is_empty() and not _world_reconnect_pending:
			if not AuthGateway.is_authenticated():
				_world_reconnect_enabled = false
				persistent_world_connection_failed.emit("Your sign-in session expired. Sign in again.")
				return
			if not AuthGateway.access_token_ready_for_connection():
				return
			_world_reconnect_elapsed += delta
			if _world_reconnect_elapsed >= _world_reconnect_delay:
				if _world_reconnect_attempts >= WORLD_MAX_RECONNECT_ATTEMPTS:
					_world_reconnect_enabled = false
					persistent_world_connection_failed.emit("Could not restore the shared world after several attempts. Return to the world browser and try again.")
				else:
					_world_reconnect_attempts += 1
					_world_reconnect_elapsed = 0.0
					# Jitter spreads simultaneous clients across a small window so a
					# regional restart does not synchronize every reconnect request.
					var base_delay := minf(pow(2.0, float(_world_reconnect_attempts)), WORLD_MAX_RECONNECT_DELAY)
					_world_reconnect_delay = minf(WORLD_MAX_RECONNECT_DELAY, base_delay * randf_range(0.8, 1.2))
					_world_reconnect_pending = true
					_world_reconnect_request_generation = _world_session_generation
					persistent_world_reconnecting.emit(_world_reconnect_attempts, WORLD_MAX_RECONNECT_ATTEMPTS)
					var headers := PackedStringArray(["Authorization: Bearer " + AuthGateway.access_token_for_request(), "Content-Type: application/json"])
					var url := AuthGateway.api_base_url + "/v1/game-servers/" + _world_server_id + "/reconnect"
					var request_error := _world_reconnect_request.request(url, headers, HTTPClient.METHOD_POST, "{}")
					if request_error != OK:
						_world_reconnect_pending = false
						_world_reconnect_elapsed = 0.0
		return
	_world_peer.poll()
	var state := _world_peer.get_ready_state()
	if state == WebSocketPeer.STATE_CONNECTING:
		_world_connect_elapsed += delta
		if _world_connect_elapsed >= WORLD_CONNECT_TIMEOUT:
			# Discard the timed-out peer immediately. Waiting for STATE_CLOSED after
			# close() can otherwise leave a stalled handshake blocking retries.
			_world_peer.close(1001, "connect_timeout")
			_world_peer = null
			_world_connect_elapsed = 0.0
			_world_ticket = ""
			_world_ticket_sent = false
			_world_ready = false
			_world_heartbeat_elapsed = 0.0
			_world_heartbeat_wait_elapsed = 0.0
			_world_heartbeat_pending = false
			_world_reconnect_elapsed = 0.0
			_world_reconnect_pending = false
			if _world_reconnect_enabled and not _world_server_id.is_empty():
				persistent_world_disconnected.emit()
			else:
				persistent_world_connection_failed.emit("The persistent-world connection timed out.")
		return
	if state == WebSocketPeer.STATE_OPEN:
		_world_connect_elapsed = 0.0
		if not _world_ticket_sent:
			_world_ticket_sent = true
			var sent := _world_peer.send_text(JSON.stringify({"type":"join_ticket","ticket":_world_ticket,"lastEventSequence":_world_last_event_sequence,"interestWindows":true}))
			_world_ticket = ""
			if sent != OK:
				_world_peer.close(1011,"ticket_send_failed")
				return
		if _world_ready:
			if _world_heartbeat_pending:
				_world_heartbeat_wait_elapsed += delta
				if _world_heartbeat_wait_elapsed >= HEARTBEAT_TIMEOUT:
					_world_peer.close(1001,"heartbeat_timeout")
					return
			else:
				_world_heartbeat_elapsed += delta
				if _world_heartbeat_elapsed >= HEARTBEAT_INTERVAL:
					if _world_peer.send_text(JSON.stringify({"type":"ping","lastSequence":_world_last_event_sequence})) != OK:
						_world_peer.close(1001,"heartbeat_send_failed")
						return
					_world_heartbeat_pending = true
					_world_heartbeat_wait_elapsed = 0.0
					_world_heartbeat_elapsed = 0.0
		while _world_peer != null and _world_peer.get_available_packet_count() > 0:
			var packet := _world_peer.get_packet()
			var parsed: Variant = JSON.parse_string(packet.get_string_from_utf8())
			if typeof(parsed) != TYPE_DICTIONARY:
				continue
			var message_type := str(parsed.get("type",""))
			if message_type == "world_joined":
				_world_ready = true
				_world_interest_windows = bool(parsed.get("interestWindows", false))
				_world_last_event_sequence = maxi(0, int(parsed.get("eventSequence", 0)))
				_world_replay_requested = false
				if _world_reconnect_attempts > 0:
					_world_reconnect_attempts = 0
					_world_reconnect_elapsed = 0.0
					_world_reconnect_delay = 1.0
					_world_reconnect_enabled = true
					persistent_world_recovered.emit(_world_server_id)
				_world_heartbeat_elapsed = 0.0
				_world_heartbeat_wait_elapsed = 0.0
				_world_heartbeat_pending = false
				persistent_world_event.emit(parsed)
				persistent_world_connected.emit(_world_server_id)
			elif message_type == "world_position_window":
				if not _world_ready or not _world_interest_windows:
					continue
				var first := int(parsed.get("fromSequence", 0))
				var last := int(parsed.get("sequence", 0))
				if last <= _world_last_event_sequence:
					continue
				if first <= 0 or first > last or first > _world_last_event_sequence + 1 or not parsed.get("members") is Array:
					if not _world_replay_requested:
						_world_replay_requested = true
						_world_peer.send_text(JSON.stringify({"type":"replay_request","lastSequence":_world_last_event_sequence}))
					continue
				_world_last_event_sequence = last
				persistent_world_event.emit(parsed)
			elif message_type == "world_sync_hint":
				if not _world_replay_requested and int(parsed.get("currentSequence",0)) > _world_last_event_sequence:
					_world_replay_requested = true
					_world_peer.send_text(JSON.stringify({"type":"replay_request","lastSequence":_world_last_event_sequence}))
			elif message_type == "replay_complete":
				_world_replay_requested = false
			elif message_type == "world_resync_required":
				_world_replay_requested = false
				# Keep the cursor until the next world_joined snapshot atomically replaces it.
				_world_peer.close(1012,"world_resync_required")
			elif message_type == "pong":
				_world_heartbeat_pending = false
				_world_heartbeat_wait_elapsed = 0.0
				_world_heartbeat_elapsed = 0.0
			elif message_type == "rejected":
				var reason := str(parsed.get("reason","connection_rejected"))
				if reason == "session_revoked":
					_handle_session_revoked()
					return
				_world_peer.close(1008,reason)
			else:
				if parsed.has("sequence"):
					var sequence := int(parsed.get("sequence", 0))
					if sequence <= _world_last_event_sequence:
						continue
					if sequence > _world_last_event_sequence + 1:
						if not _world_replay_requested:
							_world_replay_requested = true
							_world_peer.send_text(JSON.stringify({"type":"replay_request","lastSequence":_world_last_event_sequence}))
						continue
					_world_last_event_sequence = sequence
				persistent_world_event.emit(parsed)
	elif state == WebSocketPeer.STATE_CLOSED:
		var reason := _world_peer.get_close_reason()
		var was_ready := _world_ready
		_world_peer = null
		_world_connect_elapsed = 0.0
		_world_ticket = ""
		_world_ticket_sent = false
		_world_ready = false
		_world_heartbeat_elapsed = 0.0
		_world_heartbeat_wait_elapsed = 0.0
		_world_heartbeat_pending = false
		if _world_reconnect_enabled and not _world_server_id.is_empty():
			_world_reconnect_elapsed = 0.0
			_world_reconnect_pending = false
			persistent_world_disconnected.emit()
		else:
			if was_ready or not reason.is_empty():
				persistent_world_connection_failed.emit(reason if not reason.is_empty() else "connection_lost")
			_world_server_id = ""
			persistent_world_disconnected.emit()


func _is_uuid(value: String) -> bool:
	var regex := RegEx.new()
	regex.compile("^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$")
	return regex.search(value) != null

func _handle_session_revoked() -> void:
	_reconnect_enabled = false
	_world_session_generation += 1
	_world_reconnect_request_generation = -1
	if _world_reconnect_pending and _world_reconnect_request != null:
		_world_reconnect_request.cancel_request()
	_world_reconnect_enabled = false
	_world_reconnect_pending = false
	_world_connect_elapsed = 0.0
	_world_reconnect_elapsed = 0.0
	_world_reconnect_attempts = 0
	_world_reconnect_delay = 1.0
	_connection_pending = false
	_connected_emitted = false
	_reconnect_elapsed = 0.0
	_reconnect_attempts = 0
	if _peer != null:
		_peer.close(1008, "session_revoked")
	_peer = null
	_lobby_id = ""
	if _world_peer != null:
		_world_peer.close(1008, "session_revoked")
	_world_peer = null
	_world_server_id = ""
	_world_ticket = ""
	_world_ticket_sent = false
	_world_ready = false
	_world_heartbeat_elapsed = 0.0
	_world_heartbeat_wait_elapsed = 0.0
	_world_heartbeat_pending = false
	_reset_heartbeat()
	persistent_world_disconnected.emit()
	AuthGateway.invalidate_session("session_revoked")
	lobby_disconnected.emit()
	connection_failed.emit("Your account session was revoked. Sign in again to continue.")

func _reset_heartbeat() -> void:
	_heartbeat_elapsed = 0.0
	_heartbeat_wait_elapsed = 0.0
	_heartbeat_pending = false
