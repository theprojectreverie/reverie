extends Node
## Opt-in opening-story transport; uses the existing authenticated persistent socket.
signal status_changed(ready: bool, reason: String)
const GEOMETRY = preload("res://scripts/online/story_opening_geometry.gd")
var _player: Player
var _region := ""
var _owner := ""
var _server := ""
var _http: HTTPRequest
var _operation := ""
var _ready_position := false
var _owns_socket := false
var _stopping := false
var _elapsed := 0.0
var _retry_at := 0
var _attempts := 0
var _target := ""
var _failure := ""
var _travel_busy := false
var _last_notice := ""

static func pilot_enabled() -> bool:
	return OS.get_environment("REVERIE_STORY_WORLD_PILOT") == "1"

func bind_player(player: Player, region: String) -> void:
	_player = player
	_region = region
	_owner = str(AuthGateway.current_player().get("id", ""))
	_player.set_network_recovery_paused(true)
	_http = HTTPRequest.new()
	_http.timeout = 12.0
	add_child(_http)
	_http.request_completed.connect(_on_http)
	MultiplayerGateway.persistent_world_event.connect(_on_world_event)
	MultiplayerGateway.persistent_world_disconnected.connect(_on_disconnected)
	MultiplayerGateway.persistent_world_connection_failed.connect(_on_connection_failed)
	AuthGateway.authentication_changed.connect(_on_authentication_changed)
	_retry_at = Time.get_ticks_msec()

func _process(delta: float) -> void:
	if _stopping or not is_instance_valid(_player):
		return
	if _retry_at > 0 and Time.get_ticks_msec() >= _retry_at and _operation.is_empty():
		_retry_at = 0
		_discover()
	if not _ready_position or not MultiplayerGateway.is_connected_to_persistent_world():
		return
	_elapsed += delta
	if _elapsed >= 0.2:
		_elapsed = 0.0
		MultiplayerGateway.send_world_position(_player.global_position)

func _discover() -> void:
	if not AuthGateway.is_authenticated() or _owner.is_empty() or str(AuthGateway.current_player().get("id", "")) != _owner:
		_fail("authentication_required", false)
		return
	if not MultiplayerGateway.standalone_expedition_id.is_empty() or (MultiplayerGateway.is_persistent_world_reconnect_enabled() and not _owns_socket):
		_fail("leave_current_world_first", false)
		return
	_send("directory", "/v1/game-servers/story-opening", HTTPClient.METHOD_GET)

func _send(operation: String, path: String, method: HTTPClient.Method) -> void:
	if not AuthGateway.access_token_ready_for_connection():
		_fail("authentication_refresh", true)
		return
	_operation = operation
	var headers := PackedStringArray(["Authorization: Bearer " + AuthGateway.access_token_for_request(), "Content-Type: application/json"])
	var err := _http.request(AuthGateway.api_base_url + path, headers, method, "{}" if method == HTTPClient.METHOD_POST else "")
	if err != OK:
		_operation = ""
		_fail("story_world_request_failed", true)

func _on_http(result: int, code: int, _headers: PackedStringArray, bytes: PackedByteArray) -> void:
	var operation := _operation
	_operation = ""
	if _stopping or str(AuthGateway.current_player().get("id", "")) != _owner:
		return
	var data: Variant = JSON.parse_string(bytes.get_string_from_utf8())
	if result != HTTPRequest.RESULT_SUCCESS or code < 200 or code >= 300 or not data is Dictionary:
		var reason := str(data.get("error", "story_world_unavailable")) if data is Dictionary else "story_world_unavailable"
		var retryable := result != HTTPRequest.RESULT_SUCCESS or code >= 500 or code == 429 or reason in ["server_assignment_expired", "server_assignment_not_found", "already_on_server", "server_unavailable", "server_full"]
		_fail(reason, retryable)
		return
	if operation == "directory":
		var servers: Array = data.get("servers", [])
		_target = ""
		for item in servers:
			if item is Dictionary and str(item.get("region_id", "")) == _region:
				_target = str(item.get("id", ""))
				break
		if _target.is_empty():
			_fail("story_region_unavailable_or_locked", true)
			return
		var assignment: Variant = data.get("assignment")
		if assignment is Dictionary:
			var assigned_region := str(assignment.get("region_id", ""))
			var assigned_id := str(assignment.get("server_id", ""))
			if assigned_region == _region:
				_target = assigned_id
				_send("reconnect", "/v1/game-servers/" + _target + "/reconnect", HTTPClient.METHOD_POST)
			elif assigned_region in ["story_training_ground", "story_village", "story_royal_gardens"]:
				_send("leave", "/v1/game-servers/" + assigned_id + "/leave", HTTPClient.METHOD_POST)
			else:
				_fail("leave_current_world_first", false)
		else:
			_send("join", "/v1/game-servers/" + _target + "/join", HTTPClient.METHOD_POST)
	elif operation == "leave":
		_send("join", "/v1/game-servers/" + _target + "/join", HTTPClient.METHOD_POST)
	elif operation in ["join", "reconnect"]:
		_server = str(data.get("serverId", ""))
		var endpoint := str(data.get("endpointUrl", ""))
		if _server != _target or not endpoint.begins_with("ws"):
			_fail("invalid_story_assignment", false)
			return
		_owns_socket = true
		var err: Error = MultiplayerGateway.connect_to_persistent_world(_server, str(data.get("joinTicket", "")), endpoint)
		if err != OK:
			_fail("story_world_connection_failed", true)

func _on_world_event(event: Dictionary) -> void:
	if _stopping or not _owns_socket or str(event.get("type", "")) != "world_joined" or str(event.get("serverId", "")) != _server or str(event.get("playerId", "")) != _owner:
		return
	for member in event.get("members", []):
		if member is Dictionary and str(member.get("playerId", "")) == _owner:
			var point := Vector2(float(member.get("x", INF)), float(member.get("y", INF)))
			if not GEOMETRY.contains(GEOMETRY.load_region(_region), point):
				_fail("invalid_story_position", false)
				return
			_player.global_position = point
			_player.velocity = Vector2.ZERO
			_ready_position = true
			_attempts = 0
			_failure = ""
			_player.set_network_recovery_paused(false)
			_notify_status(true, "")
			return
	_fail("missing_story_player", false)

func _on_disconnected() -> void:
	if _owns_socket and not _stopping:
		_ready_position = false
		_player.set_network_recovery_paused(true)
		_notify_status(false, "reconnecting")

func _on_connection_failed(reason: String) -> void:
	if _owns_socket and not _stopping:
		_fail(reason, AuthGateway.is_authenticated() and not MultiplayerGateway.is_persistent_world_reconnect_enabled())

func _on_authentication_changed(authenticated: bool, player: Dictionary) -> void:
	if not authenticated or str(player.get("id", "")) != _owner:
		_stopping = true
		_ready_position = false
		if is_instance_valid(_player):
			_player.set_network_recovery_paused(true)
		if _http != null:
			_http.cancel_request()
		if _owns_socket:
			MultiplayerGateway.disconnect_from_persistent_world()
		_notify_status(false, "authentication_required")

func _fail(reason: String, retry: bool) -> void:
	_failure = reason
	_ready_position = false
	if is_instance_valid(_player):
		_player.set_network_recovery_paused(true)
	if retry and _attempts < 4:
		_attempts += 1
		_retry_at = Time.get_ticks_msec() + _attempts * 1000
	_notify_status(false, reason)

func _exit_tree() -> void:
	_stopping = true
	if _owns_socket:
		MultiplayerGateway.disconnect_from_persistent_world()


func is_story_ready() -> bool:
	return not _stopping and _ready_position and MultiplayerGateway.is_connected_to_persistent_world() and AuthGateway.is_authenticated() and str(AuthGateway.current_player().get("id", "")) == _owner

static func village_available(data: Dictionary) -> bool:
	var progress: Variant = data.get("progress")
	if not progress is Dictionary or progress.get("tutorialComplete") != true:
		return false
	var servers: Variant = data.get("servers")
	if not servers is Array:
		return false
	for server in servers:
		if server is Dictionary and server.get("region_id") == "story_village" and str(server.get("endpoint_url", "")).begins_with("ws"):
			return true
	return false

# Read-only preflight; destination still independently gates the actual join.
func can_travel_to_village() -> bool:
	if _travel_busy or _region != "story_training_ground" or not is_story_ready() or not AuthGateway.access_token_ready_for_connection():
		return false
	_travel_busy = true
	var request := HTTPRequest.new()
	request.timeout = 8.0
	add_child(request)
	var headers := PackedStringArray(["Authorization: Bearer " + AuthGateway.access_token_for_request()])
	var err := request.request(AuthGateway.api_base_url + "/v1/game-servers/story-opening", headers)
	if err != OK:
		request.queue_free()
		_travel_busy = false
		return false
	var response: Array = await request.request_completed
	request.queue_free()
	_travel_busy = false
	if not is_story_ready() or int(response[0]) != HTTPRequest.RESULT_SUCCESS or int(response[1]) != 200:
		return false
	var data: Variant = JSON.parse_string(response[3].get_string_from_utf8())
	return data is Dictionary and village_available(data)

static func connection_message(ready: bool, reason: String) -> String:
	if ready:
		return "Story world connected."
	match reason:
		"authentication_required": return "Sign in to access the online story."
		"story_region_unavailable_or_locked", "server_unavailable", "story_progression_required": return "Story region unavailable or locked. Try again shortly."
		"reconnecting", "authentication_refresh": return "Restoring story connection. Movement is paused."
		"leave_current_world_first": return "Leave your current multiplayer world before entering the story."
		_: return "Story connection unavailable. Movement is paused."

func _notify_status(ready: bool, reason: String) -> void:
	status_changed.emit(ready, reason)
	var message := connection_message(ready, reason)
	if message != _last_notice:
		_last_notice = message
		EventBus.toast_requested.emit(message)
