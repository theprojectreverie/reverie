extends Node
## Headless regional process. Owns its player WebSocket sessions and world relay.
## The control API issues single-use join tickets; this process redeems them directly.

@export var api_base_url := "http://127.0.0.1:8787"
@export var transport_test_mode := false
@export var server_key := "reverie-local-royal-gardens"
@export var display_name := "Royal Gardens"
@export var region_id := "castle_royal_gardens"
@export var world_endpoint_url := "ws://127.0.0.1:9080"
@export var bind_address := "127.0.0.1"
@export_range(1024, 65535) var listen_port := 9080
@export_range(1, 1000) var max_players := 100
@export var build_version := "0.1.0-dev"
@export_range(10.0, 55.0) var heartbeat_interval := 20.0
@export_range(15.0, 300.0) var save_interval := 30.0
@export_range(5.0, 30.0) var admission_timeout := 10.0
@export_range(5.0, 60.0) var reconnect_grace_seconds := 15.0

var _http: HTTPRequest
var _heartbeat: Timer
var _save_timer: Timer
var _event_http: HTTPRequest
var _recovery_http: HTTPRequest
var _replay_http: HTTPRequest
var _replay_peer_id := -1
var _replay_cursor := 0
var _lease_timer: Timer
var _event_retry_timer: Timer
var _event_queue: Array[Dictionary] = []
var _event_request_active := false
var _event_batch_count := 0
const EVENT_BATCH_SIZE := 32
var _event_batch_size := EVENT_BATCH_SIZE
const MAX_ACCEPTS_PER_FRAME := 32
const MAX_INPUT_PACKETS_PER_FRAME := 16
const MAX_INPUT_BACKLOG := 64
const MAX_INPUT_BYTES := 4096
const MAX_MESSAGES_PER_SECOND := 60
var _outbound_budget_bytes := 512 * 1024
var _event_queue_budget := 1024
var _last_pressure_log: Dictionary = {}
# At most one not-yet-admitted, validated movement proposal per live peer.
# Never modify already queued event IDs or retry batches.
var _deferred_positions: Dictionary = {}
var _coalesced_positions := 0

var _tcp_server := TCPServer.new()
var _server_id := ""
var _server_token := ""
var _world_revision := 0
var _event_sequence := 0
var _event_history: Array[Dictionary] = []
const MAX_EVENT_HISTORY := 200
var _world_state: Dictionary = {"schemaVersion": 1, "regionId": "castle_royal_gardens", "entities": [], "worldFlags": {}}
var _operation := ""
var _ready_for_heartbeat := false
var _next_peer_id := 1
var _sessions: Dictionary = {}
var _player_positions: Dictionary = {}
const OPENING_GEOMETRY = preload("res://scripts/online/story_opening_geometry.gd")
var _opening_geometry: Dictionary = {}
# Opt-in pilot: zero preserves the existing all-player wire protocol.
var _interest_radius := 0.0
const INTEREST_EXIT_MULTIPLIER := 1.2
var _committed_interest_positions: Dictionary = {}
var _player_profiles: Dictionary = {}
var _disconnect_timers: Dictionary = {}
var _shutdown_requested := false

func _ready() -> void:
	var configured_batch_size := OS.get_environment("REVERIE_SERVER_EVENT_BATCH_SIZE")
	if configured_batch_size.is_valid_int():
		_event_batch_size = clampi(int(configured_batch_size), 32, 128)
	var configured_interest := OS.get_environment("REVERIE_SERVER_INTEREST_RADIUS")
	if configured_interest.is_valid_float():
		_interest_radius = clampf(float(configured_interest), 0.0, 10000.0)
	var configured_api := OS.get_environment("REVERIE_API_BASE_URL")
	var configured_key := OS.get_environment("REVERIE_SERVER_KEY")
	var configured_name := OS.get_environment("REVERIE_SERVER_NAME")
	var configured_region := OS.get_environment("REVERIE_SERVER_REGION")
	var configured_port := OS.get_environment("REVERIE_SERVER_PORT")
	var configured_max_players := OS.get_environment("REVERIE_SERVER_MAX_PLAYERS")
	var configured_host := OS.get_environment("REVERIE_SERVER_HOST")
	var configured_endpoint := OS.get_environment("REVERIE_SERVER_ENDPOINT")
	if not configured_api.is_empty():
		api_base_url = configured_api
	if not configured_key.is_empty():
		server_key = configured_key
	if not configured_name.is_empty():
		display_name = configured_name
	if not configured_region.is_empty():
		region_id = configured_region
	_opening_geometry = OPENING_GEOMETRY.load_region(region_id)
	if region_id in ["story_training_ground", "story_village", "story_royal_gardens"] and _opening_geometry.is_empty():
		push_error("Missing opening-region geometry")
		return
	if configured_port.is_valid_int():
		listen_port = clampi(int(configured_port), 1024, 65535)
	if configured_max_players.is_valid_int():
		max_players = clampi(int(configured_max_players), 1, 1000)
	if not configured_host.is_empty():
		bind_address = configured_host
	if not configured_endpoint.is_empty():
		world_endpoint_url = configured_endpoint
	elif configured_port.is_valid_int():
		var advertised_host := configured_host if not configured_host.is_empty() and configured_host != "0.0.0.0" else "127.0.0.1"
		world_endpoint_url = "ws://" + advertised_host + ":" + str(listen_port)
	_event_queue_budget = maxi(1024, max_players * 4)
	_http = HTTPRequest.new()
	_http.timeout = 12.0
	add_child(_http)
	_http.request_completed.connect(_on_request_completed)
	_heartbeat = Timer.new()
	_heartbeat.wait_time = heartbeat_interval
	_heartbeat.timeout.connect(_send_heartbeat)
	add_child(_heartbeat)
	_save_timer = Timer.new()
	_save_timer.wait_time = save_interval
	_save_timer.timeout.connect(_save_world_state)
	add_child(_save_timer)
	_event_http = HTTPRequest.new()
	_event_http.timeout = 12.0
	_event_http.request_completed.connect(_on_world_event_completed)
	add_child(_event_http)
	_recovery_http = HTTPRequest.new()
	_recovery_http.timeout = 12.0
	_recovery_http.request_completed.connect(_on_world_recovery_completed)
	add_child(_recovery_http)
	_replay_http = HTTPRequest.new()
	_replay_http.timeout = 12.0
	_replay_http.request_completed.connect(_on_durable_replay_completed)
	add_child(_replay_http)
	_lease_timer = Timer.new()
	_lease_timer.wait_time = 15.0
	_lease_timer.timeout.connect(_renew_connection_leases)
	add_child(_lease_timer)
	_event_retry_timer = Timer.new()
	_event_retry_timer.one_shot = true
	_event_retry_timer.wait_time = 1.0
	_event_retry_timer.timeout.connect(_process_next_world_event)
	add_child(_event_retry_timer)
	if transport_test_mode:
		return
	if api_base_url.is_empty() or not api_base_url.begins_with("http"):
		push_error("Dedicated world server requires a valid API base URL.")
		return
	if not (world_endpoint_url.begins_with("ws://") or world_endpoint_url.begins_with("wss://")):
		push_error("Dedicated world endpoint must use ws:// or wss://.")
		return
	if OS.get_environment("REVERIE_SERVER_BOOTSTRAP_SECRET").length() < 32:
		push_error("Set REVERIE_SERVER_BOOTSTRAP_SECRET in the process environment; it is never stored in the project.")
		return
	_register_server()

func _process(_delta: float) -> void:
	if _ready_for_heartbeat:
		_poll_listener()
		_flush_deferred_positions()
		_poll_sessions()
		_flush_deferred_positions()
		_process_next_world_event()
		_try_save_world_state()

func _exit_tree() -> void:
	if _tcp_server.is_listening():
		_tcp_server.stop()
	for session in _sessions.values():
		var socket: WebSocketPeer = session.get("socket")
		if socket != null:
			socket.close(1001, "server_shutdown")
	if not _server_id.is_empty() and not _server_token.is_empty():
		_send_final_save_and_offline()

func _register_server() -> void:
	var body := {
		"serverKey": server_key,
		"displayName": display_name,
		"regionId": region_id,
		"endpointUrl": world_endpoint_url,
		"maxPlayers": max_players,
		"buildVersion": build_version
	}
	_operation = "register"
	var headers := PackedStringArray(["Content-Type: application/json", "x-server-bootstrap-secret: " + OS.get_environment("REVERIE_SERVER_BOOTSTRAP_SECRET")])
	var err := _http.request(api_base_url + "/v1/game-servers/register", headers, HTTPClient.METHOD_POST, JSON.stringify(body))
	if err != OK:
		_operation = ""
		push_error("Could not start dedicated server registration: " + str(err))

func _on_request_completed(result: int, response_code: int, _headers: PackedStringArray, bytes: PackedByteArray) -> void:
	var op := _operation
	_operation = ""
	if result != HTTPRequest.RESULT_SUCCESS:
		push_error("Dedicated server request failed: " + op)
		return
	var parsed: Variant = JSON.parse_string(bytes.get_string_from_utf8())
	if response_code < 200 or response_code >= 300 or typeof(parsed) != TYPE_DICTIONARY:
		push_error("Dedicated server API rejected " + op + " (HTTP " + str(response_code) + "): " + JSON.stringify(parsed))
		return
	if op == "register":
		_server_id = str(parsed.get("serverId", ""))
		_server_token = str(parsed.get("serverToken", ""))
		if _server_id.is_empty() or _server_token.length() < 32:
			push_error("Server registration response was incomplete.")
			return
		_load_world_state()
	elif op == "load":
		_world_revision = int(parsed.get("revision", 0))
		var state: Variant = parsed.get("state", {})
		if typeof(state) == TYPE_DICTIONARY:
			_world_state = state
		_world_state["regionId"] = region_id
		_event_sequence = maxi(0, int(_world_state.get("eventSequence", 0)))
		var saved_positions: Variant = _world_state.get("playerPositions", {})
		if typeof(saved_positions) == TYPE_DICTIONARY:
			for player_id in saved_positions:
				var saved_position: Variant = saved_positions[player_id]
				if typeof(saved_position) == TYPE_DICTIONARY:
					_player_positions[str(player_id)] = Vector2(float(saved_position.get("x", 0.0)), float(saved_position.get("y", 0.0)))
		var saved_profiles: Variant = _world_state.get("playerProfiles", {})
		if typeof(saved_profiles) == TYPE_DICTIONARY:
			for player_id in saved_profiles:
				var saved_profile: Variant = saved_profiles[player_id]
				if typeof(saved_profile) == TYPE_DICTIONARY:
					_player_profiles[str(player_id)] = {"name":str(saved_profile.get("name", "Adventurer")), "level":maxi(1, int(saved_profile.get("level", 1))), "title":str(saved_profile.get("title",""))}
		_recover_world_events()
	elif op == "heartbeat":
		var titles:Variant=parsed.get("titles",[])
		if titles is Array:
			var verified:Array=[]
			for entry in titles:
				if not entry is Dictionary:continue
				var id:=str(entry.get("playerId",""))
				if not _player_profiles.has(id):continue
				var title:=str(entry.get("title",""))
				_player_profiles[id]["title"]=title
				verified.append({"playerId":id,"title":title})
			if not verified.is_empty():
				_broadcast({"type":"player_titles","players":verified})
	elif op == "save":
		_world_revision = int(parsed.get("revision", _world_revision))
	elif op == "offline":
		pass

func _server_headers() -> PackedStringArray:
	return PackedStringArray(["Authorization: Bearer " + _server_token, "Content-Type: application/json"])

func _load_world_state() -> void:
	_operation = "load"
	var err := _http.request(api_base_url + "/v1/game-servers/" + _server_id + "/world-state", _server_headers(), HTTPClient.METHOD_GET)
	if err != OK:
		_operation = ""
		push_error("Could not request world-state recovery.")

func _recover_world_events() -> void:
	var url := api_base_url + "/v1/game-servers/" + _server_id + "/events?after=" + str(_event_sequence)
	var err := _recovery_http.request(url, _server_headers(), HTTPClient.METHOD_GET)
	if err != OK:
		push_error("Could not start durable world-event recovery.")
		return

func _on_world_recovery_completed(result: int, response_code: int, _headers: PackedStringArray, bytes: PackedByteArray) -> void:
	var parsed: Variant = JSON.parse_string(bytes.get_string_from_utf8())
	if result != HTTPRequest.RESULT_SUCCESS or response_code != 200 or typeof(parsed) != TYPE_DICTIONARY:
		push_error("Durable world-event recovery failed (HTTP " + str(response_code) + ").")
		return
	var current_sequence := maxi(0, int(parsed.get("currentSequence", 0)))
	if bool(parsed.get("requiresSnapshot", false)):
		_player_positions.clear()
		var active_player_ids: Dictionary = {}
		var positions: Variant = parsed.get("positions", [])
		if typeof(positions) == TYPE_ARRAY:
			for item in positions:
				if typeof(item) == TYPE_DICTIONARY:
					var player_id := str(item.get("playerId", ""))
					if player_id.is_empty():
						continue
					_player_positions[player_id] = Vector2(float(item.get("x", 0.0)), float(item.get("y", 0.0)))
					active_player_ids[player_id] = true
		for profile_player_id in _player_profiles.keys():
			if not active_player_ids.has(profile_player_id):
				_player_profiles.erase(profile_player_id)
	else:
		var events: Variant = parsed.get("events", [])
		if typeof(events) == TYPE_ARRAY:
			var expected_sequence := _event_sequence + 1
			for item in events:
				if typeof(item) != TYPE_DICTIONARY:
					continue
				var sequence := int(item.get("sequence", 0))
				if sequence != expected_sequence:
					push_error("Durable world-event recovery found a sequence gap.")
					return
				var event_type := str(item.get("type", ""))
				var player_id := str(item.get("playerId", ""))
				_event_history.append(item.duplicate(true))
				if _event_history.size() > MAX_EVENT_HISTORY:
					_event_history.pop_front()
				if event_type == "position":
					_player_positions[player_id] = Vector2(float(item.get("x", 0.0)), float(item.get("y", 0.0)))
				elif event_type == "player_joined":
					_player_profiles[player_id] = {"name":str(item.get("name", "Adventurer")), "level":maxi(1, int(item.get("level", 1))), "title":str(item.get("title",""))}
				elif event_type == "player_left":
					_player_positions.erase(player_id)
					_player_profiles.erase(player_id)
				expected_sequence += 1
	_event_sequence = current_sequence
	_world_state["eventSequence"] = _event_sequence
	_committed_interest_positions = _player_positions.duplicate()
	_start_transport()

func _renew_connection_leases() -> void:
	for peer_id in _sessions.keys():
		var session: Dictionary = _sessions[peer_id]
		var connection_id := str(session.get("connection_id", ""))
		if connection_id.is_empty():
			continue
		var request := HTTPRequest.new()
		request.timeout = 8.0
		add_child(request)
		request.request_completed.connect(_on_connection_lease_renewed.bind(int(peer_id), request), CONNECT_ONE_SHOT)
		var url := api_base_url + "/v1/game-servers/" + _server_id + "/connections/" + connection_id
		var err := request.request(url, _server_headers(), HTTPClient.METHOD_PUT, "{}")
		if err != OK:
			request.queue_free()
			_close_peer(int(peer_id), 1011, "connection_lease_unavailable")

func _on_connection_lease_renewed(result: int, response_code: int, _headers: PackedStringArray, _bytes: PackedByteArray, peer_id: int, request: HTTPRequest) -> void:
	request.queue_free()
	if result != HTTPRequest.RESULT_SUCCESS or response_code != 200:
		_close_peer(peer_id, 1011, "connection_lease_lost")

func _start_transport() -> void:
	var err := _tcp_server.listen(listen_port, bind_address)
	if err != OK:
		push_error("Dedicated player transport could not listen on port " + str(listen_port) + ": " + str(err))
		return
	_ready_for_heartbeat = true
	if not transport_test_mode:
		_send_heartbeat()
		_heartbeat.start()
		_save_timer.start()
		_lease_timer.start()
	print("Dedicated world transport listening at ", world_endpoint_url)

func _send_heartbeat() -> void:
	if not _ready_for_heartbeat or not _operation.is_empty():
		return
	_operation = "heartbeat"
	var err := _http.request(api_base_url + "/v1/game-servers/" + _server_id + "/heartbeat", _server_headers(), HTTPClient.METHOD_POST, JSON.stringify({"status":"online"}))
	if err != OK:
		_operation = ""
		push_warning("Could not send dedicated server heartbeat.")

var _checkpoint_due := false

func _save_world_state() -> void:
	_checkpoint_due = true
	_try_save_world_state()

func _try_save_world_state() -> void:
	# Keep a scheduled checkpoint pending while the durable stream is busy.
	if not _checkpoint_due or not _ready_for_heartbeat or not _operation.is_empty() or not _event_queue.is_empty() or _event_request_active or not _deferred_positions.is_empty():
		return
	_checkpoint_due = false
	var saved_positions: Dictionary = {}
	for player_id in _player_positions:
		var position: Vector2 = _player_positions[player_id]
		saved_positions[str(player_id)] = {"x":position.x,"y":position.y}
	_world_state["playerPositions"] = saved_positions
	_world_state["playerProfiles"] = _player_profiles.duplicate(true)
	_world_state["eventSequence"] = _event_sequence
	_operation = "save"
	var body := {"revision": _world_revision, "state": _world_state}
	var err := _http.request(api_base_url + "/v1/game-servers/" + _server_id + "/world-state", _server_headers(), HTTPClient.METHOD_PUT, JSON.stringify(body))
	if err != OK:
		_operation = ""
		push_warning("Could not start world-state save.")

func _poll_listener() -> void:
	var accepted := 0
	while _tcp_server.is_connection_available() and accepted < MAX_ACCEPTS_PER_FRAME:
		accepted += 1
		if _sessions.size() >= max_players * 2:
			var overflow := _tcp_server.take_connection()
			overflow.disconnect_from_host()
			continue
		var stream := _tcp_server.take_connection()
		var socket := WebSocketPeer.new()
		socket.inbound_buffer_size = 64 * 1024
		socket.outbound_buffer_size = 1024 * 1024
		socket.max_queued_packets = 256
		var err := socket.accept_stream(stream)
		if err != OK:
			stream.disconnect_from_host()
			continue
		var peer_id := _next_peer_id
		_next_peer_id += 1
		var timeout := get_tree().create_timer(admission_timeout)
		_sessions[peer_id] = {"socket":socket,"player_id":"","authenticated":false,"queued":false,"admission_timer":timeout,"ticket_prompted":false}
		timeout.timeout.connect(_on_admission_timeout.bind(peer_id), CONNECT_ONE_SHOT)

func _poll_sessions() -> void:
	for peer_id in _sessions.keys():
		if not _sessions.has(peer_id):
			continue
		var session: Dictionary = _sessions[peer_id]
		var socket: WebSocketPeer = session["socket"]
		socket.poll()
		if socket.get_ready_state() == WebSocketPeer.STATE_OPEN:
			if not session["ticket_prompted"]:
				session["ticket_prompted"] = true
				_send_peer(peer_id, {"type":"ticket_required","serverId":_server_id})
			if socket.get_available_packet_count() > MAX_INPUT_BACKLOG:
				_close_peer(int(peer_id), 1008, "input_backlog")
				continue
			var processed := 0
			while socket.get_ready_state() == WebSocketPeer.STATE_OPEN and socket.get_available_packet_count() > 0 and processed < MAX_INPUT_PACKETS_PER_FRAME:
				processed += 1
				var packet := socket.get_packet()
				if packet.size() > MAX_INPUT_BYTES:
					_close_peer(int(peer_id), 1009, "message_too_large")
					break
				if not _consume_input_budget(session):
					_close_peer(int(peer_id), 1008, "message_rate_exceeded")
					break
				if not socket.was_string_packet():
					socket.close(1003, "text_messages_only")
					break
				var message: Variant = JSON.parse_string(packet.get_string_from_utf8())
				_handle_peer_message(peer_id, message)
		elif socket.get_ready_state() in [WebSocketPeer.STATE_CLOSING, WebSocketPeer.STATE_CLOSED]:
			# A peer may remain in CLOSING when the remote TCP connection is
			# terminated without completing a WebSocket close handshake. Release
			# its durable lease as soon as the transport is no longer usable.
			_remove_peer(peer_id)

func _consume_input_budget(session: Dictionary) -> bool:
	var now := Time.get_ticks_msec()
	var started := int(session.get("input_window_started", now))
	if now - started >= 1000:
		started = now
		session["input_count"] = 0
	session["input_window_started"] = started
	var count := int(session.get("input_count", 0)) + 1
	session["input_count"] = count
	return count <= MAX_MESSAGES_PER_SECOND

func _persistence_busy() -> bool:
	return not transport_test_mode and _event_queue.size() >= _event_queue_budget

func _flush_deferred_positions() -> void:
	for peer_id in _deferred_positions.keys():
		if _persistence_busy():
			break
		var proposal: Dictionary = _deferred_positions[peer_id]
		_deferred_positions.erase(peer_id)
		var session: Dictionary = _sessions.get(peer_id, {})
		if not session.get("authenticated", false) or str(session.get("player_id", "")) != str(proposal["playerId"]):
			continue
		var socket: WebSocketPeer = session.get("socket")
		if socket == null or socket.get_ready_state() != WebSocketPeer.STATE_OPEN:
			continue
		_admit_position(int(peer_id), proposal)

func _admit_position(peer_id: int, proposal: Dictionary) -> void:
	var player_id := str(proposal["playerId"])
	_player_positions[player_id] = Vector2(float(proposal["x"]), float(proposal["y"]))
	_emit_world_event(proposal, peer_id)

func _handle_peer_message(peer_id: int, message: Variant) -> void:
	if not _sessions.has(peer_id):
		return
	if typeof(message) != TYPE_DICTIONARY:
		_send_peer(peer_id, {"type":"rejected","reason":"invalid_message"})
		return
	var session: Dictionary = _sessions[peer_id]
	if not session["authenticated"]:
		if session["queued"]:
			return
		if _persistence_busy():
			_close_peer(peer_id, 1013, "world_persistence_busy")
			return
		var ticket := str(message.get("ticket", "")) if str(message.get("type", "")) == "join_ticket" else ""
		if ticket.length() < 40 or ticket.length() > 200:
			_send_peer(peer_id, {"type":"rejected","reason":"join_ticket_required"})
			_close_peer(peer_id, 1008, "join_ticket_required")
			return
		session["interest_windows"] = _interest_radius > 0.0 and message.get("interestWindows", false) == true
		session["queued"] = true
		_sessions[peer_id] = session
		_redeem_join_ticket(peer_id, ticket)
		return
	var message_type := str(message.get("type", ""))
	if message_type == "ping":
		var client_sequence := maxi(0, int(message.get("lastSequence", 0)))
		if client_sequence < _event_sequence:
			_send_peer(peer_id, {"type":"world_sync_hint","currentSequence":_event_sequence})
		_send_peer(peer_id, {"type":"pong","serverTime":Time.get_unix_time_from_system()})
	elif message_type == "replay_request":
		_replay_events(peer_id, maxi(0, int(message.get("lastSequence", 0))))
	elif message_type == "position":
		var x := float(message.get("x", INF))
		var y := float(message.get("y", INF))
		if not is_finite(x) or not is_finite(y) or absf(x) > 100000.0 or absf(y) > 100000.0:
			_send_peer(peer_id, {"type":"rejected","reason":"invalid_position"})
			return
		var player_id := str(session["player_id"])
		var now_ms := Time.get_ticks_msec()
		var last_position_at := int(session.get("last_position_at", now_ms))
		var elapsed := maxf(float(now_ms - last_position_at) / 1000.0, 0.0)
		if elapsed < 0.04:
			return
		if not _opening_geometry.is_empty() and not OPENING_GEOMETRY.contains(_opening_geometry, Vector2(x, y)):
			_send_peer(peer_id, {"type":"rejected","reason":"region_bounds"})
			return
		var previous: Vector2 = _player_positions.get(player_id, Vector2(x, y))
		if _deferred_positions.has(peer_id):
			var pending: Dictionary = _deferred_positions[peer_id]
			previous = Vector2(float(pending["x"]), float(pending["y"]))
		var allowed_distance := 50.0 + elapsed * 900.0
		if not _opening_geometry.is_empty():
			allowed_distance = 8.0 + minf(elapsed, 0.25) * 650.0
		if previous.distance_to(Vector2(x, y)) > allowed_distance:
			_send_peer(peer_id, {"type":"rejected","reason":"movement_too_fast"})
			return
		session["last_position_at"] = now_ms
		_sessions[peer_id] = session
		var proposal := {"type":"position","playerId":player_id,"x":x,"y":y}
		if _persistence_busy() or _deferred_positions.has(peer_id):
			if _deferred_positions.has(peer_id):
				_coalesced_positions += 1
			_deferred_positions[peer_id] = proposal
		else:
			_admit_position(peer_id, proposal)
	elif message_type == "emote":
		# Cosmetic requests are not accepted while persistence is saturated.
		if _persistence_busy():
			return
		var emote_id := str(message.get("emoteId", ""))
		if emote_id not in ["wave","cheer","sad","dance"]:
			return
		var now_ms := Time.get_ticks_msec()
		if now_ms - int(session.get("last_emote_at", 0)) < 750:
			return
		session["last_emote_at"] = now_ms
		_sessions[peer_id] = session
		_emit_world_event({"type":"emote","playerId":str(session["player_id"]),"emoteId":emote_id}, peer_id)
	else:
		_send_peer(peer_id, {"type":"rejected","reason":"unsupported_event"})

func _redeem_join_ticket(peer_id: int, ticket: String) -> void:
	if not _sessions.has(peer_id):
		return
	var session: Dictionary = _sessions[peer_id]
	var connection_id := _make_event_id()
	session["connection_id"] = connection_id
	_sessions[peer_id] = session
	var request := HTTPRequest.new()
	request.timeout = 10.0
	add_child(request)
	request.request_completed.connect(_on_ticket_redeemed.bind(peer_id, request), CONNECT_ONE_SHOT)
	var url := api_base_url + "/v1/game-servers/" + _server_id + "/consume-ticket"
	var err := request.request(url, _server_headers(), HTTPClient.METHOD_POST, JSON.stringify({"ticket":ticket,"connectionId":connection_id}))
	if err != OK:
		request.queue_free()
		_send_peer(peer_id, {"type":"error","code":"ticket_validation_unavailable"})
		_close_peer(peer_id, 1011, "ticket_validation_unavailable")

func _on_ticket_redeemed(result: int, response_code: int, _headers: PackedStringArray, bytes: PackedByteArray, peer_id: int, request: HTTPRequest) -> void:
	request.queue_free()
	var parsed: Variant = JSON.parse_string(bytes.get_string_from_utf8())
	if not _sessions.has(peer_id):
		if typeof(parsed) == TYPE_DICTIONARY:
			var orphaned_connection := str(parsed.get("connectionId", ""))
			if not orphaned_connection.is_empty():
				_release_connection_lease(orphaned_connection)
		return
	if result != HTTPRequest.RESULT_SUCCESS or response_code != 200 or typeof(parsed) != TYPE_DICTIONARY:
		_send_peer(peer_id, {"type":"rejected","reason":"join_ticket_invalid_or_expired"})
		_close_peer(peer_id, 1008, "invalid_join_ticket")
		return
	var player_id := str(parsed.get("playerId", ""))
	if player_id.is_empty():
		_close_peer(peer_id, 1011, "invalid_ticket_response")
		return
	var connection_id := str(parsed.get("connectionId", ""))
	if connection_id.is_empty():
		_close_peer(peer_id, 1011, "invalid_connection_lease")
		return
	# A redemption can finish while the persistence queue fills. Release its
	# lease without admitting a player or creating an unpersistable join event.
	if _persistence_busy():
		_release_connection_lease(connection_id)
		_close_peer(peer_id, 1013, "world_persistence_busy")
		return
	var reconnect_timer: Variant = _disconnect_timers.get(player_id)
	if reconnect_timer != null:
		_disconnect_timers.erase(player_id)
	var previous_peer := _find_player_peer(player_id)
	if previous_peer >= 0:
		_deferred_positions.erase(previous_peer)
		_close_peer(previous_peer, 4001, "replaced_by_reconnect")
	var session: Dictionary = _sessions[peer_id]
	session["player_id"] = player_id
	session["connection_id"] = connection_id
	var player_profile: Variant = parsed.get("player", {})
	if typeof(player_profile) == TYPE_DICTIONARY:
		_player_profiles[player_id] = {"name":str(player_profile.get("name", "Adventurer")), "level":maxi(1, int(player_profile.get("level", 1))), "title":str(player_profile.get("title",""))}
	session["authenticated"] = true
	session["last_position_at"] = Time.get_ticks_msec()
	session["last_emote_at"] = 0
	_sessions[peer_id] = session
	var default_spawn := Vector2.ZERO if _opening_geometry.is_empty() else OPENING_GEOMETRY.spawn(_opening_geometry)
	var position: Vector2 = _player_positions.get(player_id, default_spawn)
	if not _opening_geometry.is_empty() and not OPENING_GEOMETRY.contains(_opening_geometry, position):
		position = default_spawn
	_player_positions[player_id] = position
	if not _committed_interest_positions.has(player_id):
		_committed_interest_positions[player_id] = position
	# Negotiated clients already receive the authoritative member snapshot.
	# Avoid repeating all positions/profiles from the last checkpoint in the
	# admission packet. Preserve the legacy payload for older clients.
	var admission_state := _world_state
	if bool(session.get("interest_windows", false)):
		admission_state = _world_state.duplicate()
		admission_state.erase("playerPositions")
		admission_state.erase("playerProfiles")
	_send_peer(peer_id, {"interestWindows":bool(session.get("interest_windows", false)),"type":"world_joined","serverId":_server_id,"playerId":player_id,"revision":_world_revision,"eventSequence":_event_sequence,"worldState":admission_state,"members":_snapshot_members(player_id)})
	var joined_profile: Dictionary = _player_profiles.get(player_id, {"name":"Adventurer","level":1})
	_emit_world_event({"type":"player_joined","playerId":player_id,"name":str(joined_profile.get("name","Adventurer")),"level":int(joined_profile.get("level",1)),"title":str(joined_profile.get("title",""))}, peer_id)

func _snapshot_members(local_player_id: String) -> Array:
	var members: Array = []
	var included: Dictionary = {}
	for peer_id in _sessions.keys():
		var session: Dictionary = _sessions[peer_id]
		if session["authenticated"]:
			var player_id := str(session["player_id"])
			var position: Vector2 = _player_positions.get(player_id, Vector2.ZERO)
			var profile: Dictionary = _player_profiles.get(player_id, {"name":"Adventurer","level":1})
			members.append({"playerId":player_id,"name":str(profile.get("name", "Adventurer")),"level":int(profile.get("level", 1)),"title":str(profile.get("title","")),"x":position.x,"y":position.y})
			included[player_id] = true
	# Persisted position entries remain authoritative party membership until
	# a committed player_left event removes them. This also covers peers that
	# were offline when the dedicated process restarted.
	for disconnected_id in _player_positions.keys():
		var player_id := str(disconnected_id)
		if player_id.is_empty() or included.has(player_id):
			continue
		var position: Vector2 = _player_positions.get(player_id, Vector2.ZERO)
		var profile: Dictionary = _player_profiles.get(player_id, {"name":"Adventurer","level":1})
		members.append({"playerId":player_id,"name":str(profile.get("name", "Adventurer")),"level":int(profile.get("level", 1)),"title":str(profile.get("title","")),"x":position.x,"y":position.y})
	return members

func _find_player_peer(player_id: String) -> int:
	for peer_id in _sessions.keys():
		if _sessions[peer_id]["authenticated"] and str(_sessions[peer_id]["player_id"]) == player_id:
			return int(peer_id)
	return -1

func _on_admission_timeout(peer_id: int) -> void:
	if _sessions.has(peer_id) and not _sessions[peer_id]["authenticated"]:
		_close_peer(peer_id, 1008, "join_ticket_timeout")

func _send_peer(peer_id: int, payload: Dictionary) -> void:
	if not _sessions.has(peer_id):
		return
	_send_encoded(peer_id, JSON.stringify(payload).to_utf8_buffer())

func _send_encoded(peer_id: int, encoded: PackedByteArray) -> void:
	if not _sessions.has(peer_id):
		return
	var socket: WebSocketPeer = _sessions[peer_id]["socket"]
	if socket.get_ready_state() != WebSocketPeer.STATE_OPEN:
		return
	# A slow consumer must not retain an unbounded output queue or silently
	# miss sequenced messages. Reconnect recovers from durable state.
	if socket.get_current_outbound_buffered_amount() + encoded.size() > _outbound_budget_bytes:
		_close_peer(peer_id, 1013, "slow_client")
		return
	var result := socket.send(encoded, WebSocketPeer.WRITE_MODE_TEXT)
	if result != OK:
		var now := Time.get_ticks_msec()
		if now - int(_last_pressure_log.get("send_error_detail", -1000)) >= 1000:
			_last_pressure_log["send_error_detail"] = now
			push_warning("World send failed: error=%d payload_bytes=%d buffered_bytes=%d" % [result, encoded.size(), socket.get_current_outbound_buffered_amount()])
		_close_peer(peer_id, 1013, "send_backpressure")

func _make_event_id() -> String:
	var value := Crypto.new().generate_random_bytes(16).hex_encode()
	return value.substr(0, 8) + "-" + value.substr(8, 4) + "-4" + value.substr(13, 3) + "-a" + value.substr(17, 3) + "-" + value.substr(20, 12)

func _emit_world_event(payload: Dictionary, except_peer_id: int = -1) -> void:
	if transport_test_mode:
		_event_sequence += 1
		var test_event := payload.duplicate(true)
		test_event["sequence"] = _event_sequence
		_event_history.append(test_event)
		if _event_history.size() > MAX_EVENT_HISTORY:
			_event_history.pop_front()
		_publish_committed_events([{"payload":test_event,"except_peer_id":except_peer_id}])
		return
	_event_queue.append({"event_id":_make_event_id(),"payload":payload.duplicate(true),"except_peer_id":except_peer_id})

func _process_next_world_event() -> void:
	if _event_request_active or _event_queue.is_empty() or _server_id.is_empty() or not _event_retry_timer.is_stopped():
		return
	# Freeze the batch size until commit; retries use exactly the same event IDs.
	if _event_batch_count == 0:
		_event_batch_count = mini(_event_batch_size, _event_queue.size())
	var events: Array[Dictionary] = []
	for index in _event_batch_count:
		var queued: Dictionary = _event_queue[index]
		var event: Dictionary = queued["payload"]
		var payload := event.duplicate(true)
		payload.erase("type")
		payload.erase("playerId")
		payload.erase("sequence")
		events.append({"eventId":str(queued["event_id"]),"type":str(event["type"]),"playerId":str(event["playerId"]),"payload":payload})
	var url := api_base_url + "/v1/game-servers/" + _server_id + "/events/batch"
	_event_request_active = true
	var err := _event_http.request(url, _server_headers(), HTTPClient.METHOD_POST, JSON.stringify({"events":events}))
	if err != OK:
		_event_request_active = false
		_event_retry_timer.start()

func _on_world_event_completed(result: int, response_code: int, _headers: PackedStringArray, bytes: PackedByteArray) -> void:
	_event_request_active = false
	var parsed: Variant = JSON.parse_string(bytes.get_string_from_utf8())
	if result != HTTPRequest.RESULT_SUCCESS or response_code != 200 or typeof(parsed) != TYPE_DICTIONARY:
		push_warning("World event batch persistence failed; keeping the batch queued for retry (HTTP " + str(response_code) + ").")
		_event_retry_timer.start()
		return
	var commits: Variant = parsed.get("events", [])
	if not commits is Array or commits.size() != _event_batch_count:
		push_error("Invalid world event batch acknowledgement.")
		_event_retry_timer.start()
		return
	var previous := 0
	for index in _event_batch_count:
		var commit: Variant = commits[index]
		if not commit is Dictionary or str(commit.get("eventId", "")) != str(_event_queue[index]["event_id"]):
			push_error("World event batch acknowledgement ID mismatch.")
			_event_retry_timer.start()
			return
		var sequence := int(commit.get("sequence", 0))
		if sequence <= 0 or (index > 0 and sequence != previous + 1):
			push_error("Invalid world event batch sequence.")
			_event_retry_timer.start()
			return
		previous = sequence
	var committed: Array[Dictionary] = []
	for index in _event_batch_count:
		var queued: Dictionary = _event_queue.pop_front()
		var event: Dictionary = queued["payload"]
		var sequence := int(commits[index]["sequence"])
		event["sequence"] = sequence
		_event_sequence = maxi(_event_sequence, sequence)
		_event_history.append(event)
		if _event_history.size() > MAX_EVENT_HISTORY:
			_event_history.pop_front()
		committed.append({"payload":event,"except_peer_id":int(queued.get("except_peer_id", -1))})
	_publish_committed_events(committed)
	_world_state["eventSequence"] = _event_sequence
	_event_batch_count = 0

# Position runs are contiguous durable events. Interested clients receive one
# nearby snapshot covering the run; legacy clients receive unchanged events.
func _publish_committed_events(entries: Array[Dictionary]) -> void:
	var first := 0
	var last := 0
	var has_legacy := false
	for session in _sessions.values():
		if session.get("authenticated", false) and not session.get("interest_windows", false):
			has_legacy = true
			break
	for entry in entries:
		var event: Dictionary = entry["payload"]
		var sequence := int(event["sequence"])
		if str(event["type"]) == "position":
			if first > 0 and sequence != last + 1:
				_send_interest_window(first, last)
				first = 0
			if first == 0:
				first = sequence
			last = sequence
			_committed_interest_positions[str(event["playerId"])] = Vector2(float(event["x"]), float(event["y"]))
			if has_legacy:
				_broadcast(event, int(entry["except_peer_id"]), true)
		else:
			if first > 0:
				_send_interest_window(first, last)
				first = 0
			_broadcast(event, int(entry["except_peer_id"]), false)
	if first > 0:
		_send_interest_window(first, last)

func _interest_members(player_id: String, previously_visible: Dictionary = {}) -> Array[Dictionary]:
	var members: Array[Dictionary] = []
	if not _committed_interest_positions.has(player_id):
		return members
	var center: Vector2 = _committed_interest_positions[player_id]
	var radius_squared := _interest_radius * _interest_radius
	var exit_squared := radius_squared * INTEREST_EXIT_MULTIPLIER * INTEREST_EXIT_MULTIPLIER
	for other in _committed_interest_positions:
		if str(other) == player_id:
			continue
		var position: Vector2 = _committed_interest_positions[other]
		var limit := exit_squared if previously_visible.has(other) else radius_squared
		if center.distance_squared_to(position) > limit:
			continue
		var profile: Dictionary = _player_profiles.get(other, {})
		members.append({"playerId":str(other),"name":str(profile.get("name","Adventurer")),"title":str(profile.get("title","")),"x":position.x,"y":position.y})
	return members

func _send_interest_window(first: int, last: int) -> void:
	if _interest_radius <= 0.0:
		return
	for peer_id in _sessions.keys():
		var session: Dictionary = _sessions[peer_id]
		if session.get("authenticated", false) and session.get("interest_windows", false):
			var members := _interest_members(str(session["player_id"]), session.get("interest_visible", {}))
			var visible_now: Dictionary = {}
			for member in members:
				visible_now[str(member["playerId"])] = true
			session["interest_visible"] = visible_now
			_send_peer(int(peer_id), {"type":"world_position_window","fromSequence":first,"sequence":last,"members":members})

func _replay_events(peer_id: int, last_sequence: int) -> void:
	if not _sessions.has(peer_id):
		return
	if _replay_peer_id >= 0:
		_send_peer(peer_id, {"type":"world_resync_required","reason":"replay_busy"})
		return
	_replay_peer_id = peer_id
	_replay_cursor = last_sequence
	var url := api_base_url + "/v1/game-servers/" + _server_id + "/events?after=" + str(last_sequence)
	var err := _replay_http.request(url, _server_headers(), HTTPClient.METHOD_GET)
	if err != OK:
		_replay_peer_id = -1
		_send_peer(peer_id, {"type":"world_resync_required","reason":"replay_unavailable"})

func _on_durable_replay_completed(result: int, response_code: int, _headers: PackedStringArray, bytes: PackedByteArray) -> void:
	var peer_id := _replay_peer_id
	var cursor := _replay_cursor
	_replay_peer_id = -1
	if peer_id < 0 or not _sessions.has(peer_id):
		return
	var parsed: Variant = JSON.parse_string(bytes.get_string_from_utf8())
	if result != HTTPRequest.RESULT_SUCCESS or response_code != 200 or typeof(parsed) != TYPE_DICTIONARY:
		_send_peer(peer_id, {"type":"world_resync_required","reason":"replay_unavailable"})
		return
	var current_sequence := int(parsed.get("currentSequence", cursor))
	if bool(parsed.get("requiresSnapshot", false)):
		_send_peer(peer_id, {"type":"world_resync_required","reason":"replay_window_expired","currentSequence":current_sequence,"positions":parsed.get("positions", [])})
		return
	var events: Variant = parsed.get("events", [])
	if typeof(events) != TYPE_ARRAY:
		_send_peer(peer_id, {"type":"world_resync_required","reason":"invalid_replay_payload"})
		return
	var expected := cursor + 1
	var ordered: Array[Dictionary] = []
	for item in events:
		if typeof(item) != TYPE_DICTIONARY:
			_send_peer(peer_id, {"type":"world_resync_required","reason":"invalid_replay_event"})
			return
		var event: Dictionary = item
		var sequence := int(event.get("sequence", 0))
		if sequence != expected:
			_send_peer(peer_id, {"type":"world_resync_required","reason":"replay_sequence_gap","currentSequence":current_sequence})
			return
		ordered.append(event)
		expected += 1
	if expected - 1 != current_sequence:
		_send_peer(peer_id, {"type":"world_resync_required","reason":"replay_incomplete","currentSequence":current_sequence})
		return
	for event in ordered:
		_send_peer(peer_id, event)
	_send_peer(peer_id, {"type":"replay_complete","lastSequence":current_sequence,"currentSequence":current_sequence})
func _broadcast(payload: Dictionary, except_peer_id: int = -1, legacy_position_only: bool = false) -> void:
	# Serialize once, not once per recipient. Preserve the exact wire payload.
	var encoded := JSON.stringify(payload).to_utf8_buffer()
	for peer_id in _sessions.keys():
		var session: Dictionary = _sessions[peer_id]
		if not session["authenticated"]:
			continue
		var interested := bool(session.get("interest_windows", false))
		if legacy_position_only and interested:
			continue
		# Negotiated clients need their own sequenced non-position events too.
		if int(peer_id) == except_peer_id and (not interested or not payload.has("sequence")):
			continue
		_send_encoded(int(peer_id), encoded)

func _close_peer(peer_id: int, code: int, reason: String) -> void:
	if code == 1013 or reason in ["input_backlog", "message_rate_exceeded", "message_too_large"]:
		var now := Time.get_ticks_msec()
		if now - int(_last_pressure_log.get(reason, -1000)) >= 1000:
			_last_pressure_log[reason] = now
			push_warning("Transport pressure: %s; pending events=%d/%d; sessions=%d" % [reason, _event_queue.size(), _event_queue_budget, _sessions.size()])
	if _sessions.has(peer_id):
		var socket: WebSocketPeer = _sessions[peer_id]["socket"]
		socket.close(code, reason)

func _release_connection_lease(connection_id: String) -> void:
	var request := HTTPRequest.new()
	request.timeout = 8.0
	add_child(request)
	request.request_completed.connect(func(_result: int, _code: int, _headers: PackedStringArray, _body: PackedByteArray) -> void: request.queue_free(), CONNECT_ONE_SHOT)
	var url := api_base_url + "/v1/game-servers/" + _server_id + "/connections/" + connection_id
	if request.request(url, _server_headers(), HTTPClient.METHOD_DELETE, "{}") != OK:
		request.queue_free()

func _remove_peer(peer_id: int) -> void:
	if not _sessions.has(peer_id):
		return
	var session: Dictionary = _sessions[peer_id]
	var player_id := str(session["player_id"])
	var connection_id := str(session.get("connection_id", ""))
	_sessions.erase(peer_id)
	_deferred_positions.erase(peer_id)
	if not connection_id.is_empty():
		_release_connection_lease(connection_id)
	if player_id.is_empty() or _find_player_peer(player_id) >= 0:
		return
	_broadcast({"type":"player_connection_lost","playerId":player_id,"reconnectGraceMs":int(reconnect_grace_seconds * 1000.0)})
	var timer := get_tree().create_timer(reconnect_grace_seconds)
	_disconnect_timers[player_id] = timer
	timer.timeout.connect(_expire_player_session.bind(player_id, timer), CONNECT_ONE_SHOT)

func _expire_player_session(player_id: String, timer: SceneTreeTimer) -> void:
	if _disconnect_timers.get(player_id) != timer:
		return
	_disconnect_timers.erase(player_id)
	if _find_player_peer(player_id) >= 0:
		return
	_request_player_disconnect(player_id)

func _request_player_disconnect(player_id: String) -> void:
	if _find_player_peer(player_id) >= 0:
		return
	# Do not remove the database assignment while its accepted events still
	# await commit; that would turn retries into permanent assignment errors.
	for queued in _event_queue:
		if str(queued.get("payload", {}).get("playerId", "")) == player_id:
			_schedule_player_disconnect_retry(player_id)
			return
	var request := HTTPRequest.new()
	request.timeout = 10.0
	add_child(request)
	request.request_completed.connect(_on_player_disconnect_completed.bind(player_id, request), CONNECT_ONE_SHOT)
	var url := api_base_url + "/v1/game-servers/" + _server_id + "/disconnect"
	var err := request.request(url, _server_headers(), HTTPClient.METHOD_POST, JSON.stringify({"playerId":player_id}))
	if err != OK:
		request.queue_free()
		_schedule_player_disconnect_retry(player_id)

func _on_player_disconnect_completed(result: int, response_code: int, _headers: PackedStringArray, bytes: PackedByteArray, player_id: String, request: HTTPRequest) -> void:
	request.queue_free()
	if _find_player_peer(player_id) >= 0:
		return
	var parsed: Variant = JSON.parse_string(bytes.get_string_from_utf8())
	if result != HTTPRequest.RESULT_SUCCESS or response_code != 200 or typeof(parsed) != TYPE_DICTIONARY:
		_schedule_player_disconnect_retry(player_id)
		return
	_player_positions.erase(player_id)
	_committed_interest_positions.erase(player_id)
	_player_profiles.erase(player_id)
	var sequence := int(parsed.get("sequence", _event_sequence))
	if sequence > _event_sequence:
		_event_sequence = sequence
		var event := {"type":"player_left","playerId":player_id,"sequence":sequence}
		_event_history.append(event)
		if _event_history.size() > MAX_EVENT_HISTORY:
			_event_history.pop_front()
		_world_state["eventSequence"] = _event_sequence
		_broadcast(event)

func _schedule_player_disconnect_retry(player_id: String) -> void:
	var timer := get_tree().create_timer(5.0)
	_disconnect_timers[player_id] = timer
	timer.timeout.connect(_retry_player_disconnect.bind(player_id, timer), CONNECT_ONE_SHOT)

func _retry_player_disconnect(player_id: String, timer: SceneTreeTimer) -> void:
	if _disconnect_timers.get(player_id) != timer:
		return
	_disconnect_timers.erase(player_id)
	if _find_player_peer(player_id) < 0:
		_request_player_disconnect(player_id)
func _send_final_save_and_offline() -> void:
	if _shutdown_requested:
		return
	_shutdown_requested = true
	if _http == null or not _http.is_inside_tree():
		return
	if _operation.is_empty():
		_operation = "offline"
		var err := _http.request(api_base_url + "/v1/game-servers/" + _server_id + "/heartbeat", _server_headers(), HTTPClient.METHOD_POST, JSON.stringify({"status":"offline"}))
		if err != OK:
			_operation = ""
