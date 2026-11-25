extends Node
## Authenticated client transport for server-authoritative PvP.
signal pvp_result(operation: String, success: bool, payload: Dictionary)
signal match_state_updated(state: Dictionary, events: Array)

@export var api_base_url := "http://127.0.0.1:8787"
@export_range(5, 60) var request_timeout_seconds := 20

@onready var queue_join_request: HTTPRequest = $QueueJoinRequest
@onready var queue_leave_request: HTTPRequest = $QueueLeaveRequest
@onready var queue_status_request: HTTPRequest = $QueueStatusRequest
@onready var match_events_request: HTTPRequest = $MatchEventsRequest
@onready var match_action_request: HTTPRequest = $MatchActionRequest
@onready var match_surrender_request: HTTPRequest = $MatchSurrenderRequest
@onready var queue_status_timer: Timer = $QueueStatusTimer
@onready var match_events_timer: Timer = $MatchEventsTimer

var active_match_id := ""
var last_event_sequence := 0
var match_state: Dictionary = {}
var _polling_enabled := false

func _ready() -> void:
	for request_node in [queue_join_request, queue_leave_request, queue_status_request, match_events_request, match_action_request, match_surrender_request]:
		request_node.timeout = request_timeout_seconds
	queue_join_request.request_completed.connect(_on_queue_join_completed)
	queue_leave_request.request_completed.connect(_on_queue_leave_completed)
	queue_status_request.request_completed.connect(_on_queue_status_completed)
	match_events_request.request_completed.connect(_on_match_events_completed)
	match_action_request.request_completed.connect(_on_match_action_completed)
	match_surrender_request.request_completed.connect(_on_match_surrender_completed)


	AuthGateway.authentication_changed.connect(_on_authentication_changed)

func queue_join() -> Error:
	if not _session_ready():
		return ERR_UNAUTHORIZED if not AuthGateway.is_authenticated() else ERR_BUSY
	if not _idle(queue_join_request):
		return ERR_BUSY
	_polling_enabled = true
	queue_status_timer.start()
	match_events_timer.start()
	return queue_join_request.request(api_base_url + "/v1/pvp/queue/join", _headers(), HTTPClient.METHOD_POST, "{}")

func queue_leave() -> Error:
	if not _session_ready():
		return ERR_UNAUTHORIZED if not AuthGateway.is_authenticated() else ERR_BUSY
	if not _idle(queue_leave_request):
		return ERR_BUSY
	return queue_leave_request.request(api_base_url + "/v1/pvp/queue/leave", _headers(), HTTPClient.METHOD_POST, "{}")

func refresh_queue_status() -> Error:
	if not _session_ready():
		return ERR_UNAUTHORIZED if not AuthGateway.is_authenticated() else ERR_BUSY
	if not _idle(queue_status_request):
		return ERR_BUSY
	return queue_status_request.request(api_base_url + "/v1/pvp/queue/status", _headers())

func fetch_match_events() -> Error:
	if not _session_ready():
		return ERR_UNAUTHORIZED if not AuthGateway.is_authenticated() else ERR_BUSY
	if active_match_id.is_empty() or not _idle(match_events_request):
		return ERR_INVALID_PARAMETER if active_match_id.is_empty() else ERR_BUSY
	var url := api_base_url + "/v1/pvp/matches/" + active_match_id.uri_encode() + "/events?after=" + str(last_event_sequence)
	return match_events_request.request(url, _headers())

func submit_action(actor_uid: String, skill_id: String, target_uids: Array[String]) -> Error:
	if not _session_ready():
		return ERR_UNAUTHORIZED if not AuthGateway.is_authenticated() else ERR_BUSY
	if active_match_id.is_empty() or actor_uid.is_empty() or skill_id.is_empty():
		return ERR_INVALID_PARAMETER
	if not _idle(match_action_request):
		return ERR_BUSY
	var sequence := int(match_state.get("sequence", -1)) + 1
	if sequence < 1:
		return ERR_UNCONFIGURED
	var body := {"actorUid": actor_uid, "skillId": skill_id, "targetUids": target_uids, "sequence": sequence}
	return match_action_request.request(
		api_base_url + "/v1/pvp/matches/" + active_match_id.uri_encode() + "/action",
		_headers(), HTTPClient.METHOD_POST, JSON.stringify(body)
	)

func surrender_match() -> Error:
	if not _session_ready():
		return ERR_UNAUTHORIZED if not AuthGateway.is_authenticated() else ERR_BUSY
	if active_match_id.is_empty():
		return ERR_INVALID_PARAMETER
	if not _idle(match_surrender_request):
		return ERR_BUSY
	return match_surrender_request.request(
		api_base_url + "/v1/pvp/matches/" + active_match_id.uri_encode() + "/surrender",
		_headers(), HTTPClient.METHOD_POST, "{}"
	)

func begin_polling() -> void:
	_polling_enabled = true
	queue_status_timer.start()
	match_events_timer.start()
	refresh_queue_status()

func stop_polling() -> void:
	_polling_enabled = false
	queue_status_timer.stop()
	match_events_timer.stop()

func clear_match() -> void:
	active_match_id = ""
	last_event_sequence = 0
	match_state.clear()
	match_state_updated.emit({}, [])

func _poll_match_events() -> void:
	if _polling_enabled and not active_match_id.is_empty() and _idle(match_events_request):
		fetch_match_events()

func _session_ready() -> bool:
	return AuthGateway.is_authenticated() and AuthGateway.access_token_ready_for_connection()

func _headers() -> PackedStringArray:
	return PackedStringArray(["Content-Type: application/json", "Authorization: Bearer " + AuthGateway.access_token_for_request()])

func _idle(request_node: HTTPRequest) -> bool:
	return request_node.get_http_client_status() == HTTPClient.STATUS_DISCONNECTED

func _parse(body: PackedByteArray) -> Dictionary:
	if body.is_empty():
		return {}
	var parsed: Variant = JSON.parse_string(body.get_string_from_utf8())
	return parsed if typeof(parsed) == TYPE_DICTIONARY else {}

func _emit(operation: String, result: int, code: int, body: PackedByteArray) -> Dictionary:
	var payload := _parse(body)
	var success := result == HTTPRequest.RESULT_SUCCESS and code >= 200 and code < 300
	pvp_result.emit(operation, success, payload if not payload.is_empty() else {"error": "network_or_server_error", "http_status": code, "result": result})
	return payload

func _on_queue_join_completed(result: int, code: int, _headers_received: PackedStringArray, body: PackedByteArray) -> void:
	var payload := _emit("queue_join", result, code, body)
	if result == HTTPRequest.RESULT_SUCCESS and code >= 200 and code < 300:
		_consume_queue_payload(payload)

func _on_queue_leave_completed(result: int, code: int, _headers_received: PackedStringArray, body: PackedByteArray) -> void:
	var payload := _emit("queue_leave", result, code, body)
	if result == HTTPRequest.RESULT_SUCCESS and code >= 200 and code < 300:
		if str(payload.get("status", "")) == "cancelled" and active_match_id.is_empty():
			stop_polling()

func _on_queue_status_completed(result: int, code: int, _headers_received: PackedStringArray, body: PackedByteArray) -> void:
	var payload := _emit("queue_status", result, code, body)
	if result == HTTPRequest.RESULT_SUCCESS and code >= 200 and code < 300:
		_consume_queue_payload(payload)

func _consume_queue_payload(payload: Dictionary) -> void:
	var status := str(payload.get("status", ""))
	var match_id := str(payload.get("matchId", ""))
	if status == "matched" and not match_id.is_empty() and bool(payload.get("combatReady", false)):
		if active_match_id != match_id:
			active_match_id = match_id
			last_event_sequence = 0
			match_state.clear()
		if _idle(match_events_request):
			fetch_match_events()
	elif status == "not_queued" and active_match_id.is_empty():
		last_event_sequence = 0
		match_state.clear()

func _on_match_events_completed(result: int, code: int, _headers_received: PackedStringArray, body: PackedByteArray) -> void:
	var payload := _emit("match_events", result, code, body)
	if result != HTTPRequest.RESULT_SUCCESS or code < 200 or code >= 300:
		return
	if not _session_ready() or active_match_id.is_empty():
		return
	var received: Array = payload.get("events", [])
	var expected_sequence := last_event_sequence + 1
	for item in received:
		if typeof(item) != TYPE_DICTIONARY:
			pvp_result.emit("match_events", false, {"error": "invalid_event_payload"})
			return
		var sequence := int(item.get("sequence", 0))
		if sequence <= last_event_sequence:
			continue
		if sequence != expected_sequence:
			pvp_result.emit("match_events", false, {"error": "event_sequence_gap", "expected": expected_sequence, "received": sequence})
			return
		expected_sequence += 1
	if typeof(payload.get("state", null)) == TYPE_DICTIONARY:
		match_state = (payload["state"] as Dictionary).duplicate(true)
	if not received.is_empty():
		last_event_sequence = expected_sequence - 1
	match_state_updated.emit(match_state.duplicate(true), received.duplicate(true))
	if bool(payload.get("hasMoreEvents", false)):
		call_deferred("fetch_match_events")
	if str(payload.get("status", "")) in ["completed", "expired", "cancelled"]:
		stop_polling()
func _on_match_action_completed(result: int, code: int, _headers_received: PackedStringArray, body: PackedByteArray) -> void:
	var payload := _emit("match_action", result, code, body)
	if result == HTTPRequest.RESULT_SUCCESS and code >= 200 and code < 300:
		if typeof(payload.get("events", null)) == TYPE_ARRAY:
			fetch_match_events()

func _on_match_surrender_completed(result: int, code: int, _headers_received: PackedStringArray, body: PackedByteArray) -> void:
	var payload := _emit("match_surrender", result, code, body)
	if result == HTTPRequest.RESULT_SUCCESS and code >= 200 and code < 300:
		fetch_match_events()

func _on_authentication_changed(authenticated: bool, _player: Dictionary) -> void:
	if not authenticated:
		stop_polling()
		clear_match()
