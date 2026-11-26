extends Node
## Authenticated co-op lobby API transport. Lobby state is always read from the server.
signal lobby_result(operation: String, success: bool, payload: Dictionary)

@export var api_base_url := "http://127.0.0.1:8787"
@export_range(5, 60) var request_timeout_seconds := 15

@onready var create_request: HTTPRequest = $CreateRequest
@onready var join_request: HTTPRequest = $JoinRequest
@onready var current_request: HTTPRequest = $CurrentRequest
@onready var leave_request: HTTPRequest = $LeaveRequest

var _pending_operation := ""
var _pending_lobby_id := ""

func _ready() -> void:
	if OS.has_feature("reverie_public_alpha"):
		api_base_url=preload("res://scripts/online/connection_profile.gd").api_origin(true)
	for request_node in [create_request, join_request, current_request, leave_request]:
		request_node.timeout = request_timeout_seconds
	create_request.request_completed.connect(_on_create_completed)
	join_request.request_completed.connect(_on_join_completed)
	current_request.request_completed.connect(_on_current_completed)
	leave_request.request_completed.connect(_on_leave_completed)

func _session_ready() -> bool:
	return AuthGateway.is_authenticated() and AuthGateway.access_token_ready_for_connection()

func create_lobby(region_id: String = "royal_gardens", max_members: int = 4) -> Error:
	if not AuthGateway.is_authenticated():
		return ERR_UNAUTHORIZED
	if not _session_ready():
		return ERR_BUSY
	if region_id.strip_edges().length() < 2 or max_members < 2 or max_members > 4:
		return ERR_INVALID_PARAMETER
	if not _request_idle():
		return ERR_BUSY
	_pending_operation = "create"
	return create_request.request(
		api_base_url + "/v1/co-op/lobbies",
		_headers(),
		HTTPClient.METHOD_POST,
		JSON.stringify({"regionId": region_id.strip_edges().to_lower(), "maxMembers": max_members})
	)

func join_lobby(invite_code: String) -> Error:
	if not AuthGateway.is_authenticated():
		return ERR_UNAUTHORIZED
	if not _session_ready():
		return ERR_BUSY
	if invite_code.strip_edges().length() < 20:
		return ERR_INVALID_PARAMETER
	if not _request_idle():
		return ERR_BUSY
	_pending_operation = "join"
	return join_request.request(
		api_base_url + "/v1/co-op/lobbies/join",
		_headers(),
		HTTPClient.METHOD_POST,
		JSON.stringify({"inviteCode": invite_code.strip_edges()})
	)

func fetch_current_lobby() -> Error:
	if not AuthGateway.is_authenticated():
		return ERR_UNAUTHORIZED
	if not _session_ready():
		return ERR_BUSY
	if not _request_idle():
		return ERR_BUSY
	_pending_operation = "current"
	return current_request.request(api_base_url + "/v1/co-op/lobbies/current", _headers())

func leave_lobby(lobby_id: String) -> Error:
	if not AuthGateway.is_authenticated():
		return ERR_UNAUTHORIZED
	if not _session_ready():
		return ERR_BUSY
	if not _is_uuid(lobby_id):
		return ERR_INVALID_PARAMETER
	if not _request_idle():
		return ERR_BUSY
	_pending_operation = "leave"
	_pending_lobby_id = lobby_id
	return leave_request.request(
		api_base_url + "/v1/co-op/lobbies/" + lobby_id.uri_encode() + "/leave",
		_headers(),
		HTTPClient.METHOD_POST,
		"{}"
	)

func _request_idle() -> bool:
	for request_node in [create_request, join_request, current_request, leave_request]:
		if request_node.get_http_client_status() != HTTPClient.STATUS_DISCONNECTED:
			return false
	return true

func _headers() -> PackedStringArray:
	return PackedStringArray([
		"Content-Type: application/json",
		"Authorization: Bearer " + AuthGateway.access_token_for_request()
	])

func _is_uuid(value: String) -> bool:
	var pattern := RegEx.new()
	pattern.compile("^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$")
	return pattern.search(value.strip_edges()) != null

func _on_create_completed(result: int, response_code: int, _headers_received: PackedStringArray, body: PackedByteArray) -> void:
	_emit_result("create", result, response_code, body)

func _on_join_completed(result: int, response_code: int, _headers_received: PackedStringArray, body: PackedByteArray) -> void:
	_emit_result("join", result, response_code, body)

func _on_current_completed(result: int, response_code: int, _headers_received: PackedStringArray, body: PackedByteArray) -> void:
	_emit_result("current", result, response_code, body)

func _on_leave_completed(result: int, response_code: int, _headers_received: PackedStringArray, body: PackedByteArray) -> void:
	_emit_result("leave", result, response_code, body)

func _emit_result(operation: String, result: int, response_code: int, body: PackedByteArray) -> void:
	var parsed: Variant = JSON.parse_string(body.get_string_from_utf8()) if not body.is_empty() else {}
	var payload: Dictionary = parsed if typeof(parsed) == TYPE_DICTIONARY else {}
	var success := result == HTTPRequest.RESULT_SUCCESS and response_code >= 200 and response_code < 300
	_pending_operation = ""
	_pending_lobby_id = ""
	lobby_result.emit(operation, success, payload if not payload.is_empty() else {
		"error": "network_or_server_error",
		"result": result,
		"http_status": response_code
	})
