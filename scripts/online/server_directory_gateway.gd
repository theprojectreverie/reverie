extends Node
## Client-side directory and assignment requests for persistent regional game servers.
signal server_list_received(servers: Array)
signal assignment_received(server: Dictionary)
signal request_failed(operation: String, reason: String)

@export var api_base_url := "http://127.0.0.1:8787"
@onready var request: HTTPRequest = $HTTPRequest
var _operation := ""
var _server_id := ""
## Ephemeral handoff credential; never write this value to disk or logs.
var pending_join_ticket := ""
var pending_join_ticket_expires_at := ""
var pending_world_endpoint := ""

func _ready() -> void:
	if preload("res://scripts/online/connection_profile.gd").is_public_alpha():
		api_base_url=preload("res://scripts/online/connection_profile.gd").api_origin(true)
	request.request_completed.connect(_on_request_completed)
	request.timeout = 12.0

func list_servers() -> Error:
	if not AuthGateway.is_authenticated():
		return ERR_UNAUTHORIZED
	return _send("list", "/v1/game-servers", HTTPClient.METHOD_GET)

func join_server(server_id: String, allow_region_fallback: bool = false) -> Error:
	if not AuthGateway.is_authenticated() or not _is_uuid(server_id):
		return ERR_UNAUTHORIZED if not AuthGateway.is_authenticated() else ERR_INVALID_PARAMETER
	var result := _send("join", "/v1/game-servers/" + server_id + "/join", HTTPClient.METHOD_POST, {"allowRegionFallback":allow_region_fallback})
	if result == OK:
		_server_id = server_id
		clear_pending_join_ticket()
	return result

func reconnect_server(server_id: String) -> Error:
	if not AuthGateway.is_authenticated() or not _is_uuid(server_id):
		return ERR_UNAUTHORIZED if not AuthGateway.is_authenticated() else ERR_INVALID_PARAMETER
	var result := _send("reconnect", "/v1/game-servers/" + server_id + "/reconnect", HTTPClient.METHOD_POST)
	if result == OK:
		_server_id = server_id
		clear_pending_join_ticket()
	return result

func clear_pending_join_ticket() -> void:
	pending_join_ticket = ""
	pending_join_ticket_expires_at = ""
	pending_world_endpoint = ""

func leave_server(server_id: String) -> Error:
	if not AuthGateway.is_authenticated() or not _is_uuid(server_id):
		return ERR_UNAUTHORIZED if not AuthGateway.is_authenticated() else ERR_INVALID_PARAMETER
	var result := _send("leave", "/v1/game-servers/" + server_id + "/leave", HTTPClient.METHOD_POST)
	if result == OK:
		_server_id = server_id
	return result

func _send(operation: String, path: String, method: HTTPClient.Method, payload: Dictionary = {}) -> Error:
	if not _operation.is_empty():
		return ERR_BUSY
	if not AuthGateway.access_token_ready_for_connection():
		return ERR_BUSY
	_operation = operation
	var headers := PackedStringArray([
		"Authorization: Bearer " + AuthGateway.access_token_for_request(),
		"Content-Type: application/json"
	])
	var result := request.request(api_base_url + path, headers, method, JSON.stringify(payload) if method == HTTPClient.METHOD_POST else "")
	if result != OK:
		_operation = ""
	return result

func _on_request_completed(result: int, response_code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
	var operation := _operation
	_operation = ""
	if result != HTTPRequest.RESULT_SUCCESS:
		request_failed.emit(operation, "Could not reach the server directory.")
		return
	var parsed: Variant = JSON.parse_string(body.get_string_from_utf8())
	if response_code < 200 or response_code >= 300 or typeof(parsed) != TYPE_DICTIONARY:
		var reason := str(parsed.get("error", "Server request failed.")) if typeof(parsed) == TYPE_DICTIONARY else "Invalid server response."
		request_failed.emit(operation, reason)
		return
	match operation:
		"list":
			var servers: Variant = parsed.get("servers", [])
			server_list_received.emit(servers if typeof(servers) == TYPE_ARRAY else [])
		"join", "reconnect":
			pending_join_ticket = str(parsed.get("joinTicket", ""))
			pending_join_ticket_expires_at = str(parsed.get("ticketExpiresAt", ""))
			pending_world_endpoint = str(parsed.get("endpointUrl", ""))
			assignment_received.emit(parsed)
		"leave":
			assignment_received.emit({"status":"left","serverId":_server_id})

func _is_uuid(value: String) -> bool:
	var pattern := RegEx.new()
	pattern.compile("^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$")
	return pattern.search(value) != null
