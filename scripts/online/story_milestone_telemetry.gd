extends Node
## Uploads only story milestones reached through a successful, signed-in play transition.
## Existing save data is intentionally never inspected or backfilled.

const QUEUE_PATH := "user://story_milestone_telemetry.json"
const ENDPOINT := "/v1/progression/milestones"
const RETRY_DELAY_MSEC := 15000
const MILESTONE_IDS := [
	"village", "royal_gardens", "royal_gate", "willow_fields",
	"elderwood_grove", "forsaken_ruins", "ruined_tower", "chapter_complete"
]
const SCENE_MILESTONES := {
	"res://scenes/world/village/imported_village/village_playable.tscn": "village",
	"res://scenes/world/six_zone_reverie/individual_zones/zone_01_royal_gardens_standalone.tscn": "royal_gardens",
	"res://scenes/world/six_zone_reverie/individual_zones/zone_02_royal_gate_standalone.tscn": "royal_gate",
	"res://scenes/world/six_zone_reverie/individual_zones/zone_03_willow_fields_standalone.tscn": "willow_fields",
	"res://scenes/world/six_zone_reverie/individual_zones/zone_04_elderwood_grove_standalone.tscn": "elderwood_grove",
	"res://scenes/world/six_zone_reverie/individual_zones/zone_05_forsaken_ruins_standalone.tscn": "forsaken_ruins",
	"res://scenes/world/six_zone_reverie/individual_zones/zone_06_ruined_tower_standalone.tscn": "ruined_tower"
}

var _http: HTTPRequest
var _auth_gateway: Node
var _pending_by_player: Dictionary = {}
var _active_player_id := ""
var _inflight_player_id := ""
var _inflight_milestone := ""
var _retry_after_msec := 0


static func milestone_for_scene(scene_path: String) -> String:
	return str(SCENE_MILESTONES.get(scene_path, ""))


static func is_milestone_id_valid(milestone_id: String) -> bool:
	return milestone_id in MILESTONE_IDS


static func should_record(authenticated: bool, milestone_id: String) -> bool:
	return authenticated and is_milestone_id_valid(milestone_id)


func _ready() -> void:
	_http = HTTPRequest.new()
	_http.timeout = 10.0
	add_child(_http)
	_http.request_completed.connect(_on_request_completed)
	_auth_gateway = get_node_or_null("/root/AuthGateway")
	if _auth_gateway == null:
		return
	_load_pending()
	if _auth_gateway.has_signal("authentication_changed"):
		_auth_gateway.connect("authentication_changed", _on_authentication_changed)
	if bool(_auth_gateway.call("is_authenticated")):
		_on_authentication_changed(true, _auth_gateway.call("current_player"))


func _process(_delta: float) -> void:
	if not _inflight_milestone.is_empty() or Time.get_ticks_msec() < _retry_after_msec:
		return
	_flush_next()


func record_scene_transition(scene_path: String) -> void:
	_record_milestone(milestone_for_scene(scene_path))


func record_chapter_complete() -> void:
	_record_milestone("chapter_complete")


func _record_milestone(milestone_id: String) -> void:
	if not should_record(_auth_gateway != null and bool(_auth_gateway.call("is_authenticated")), milestone_id):
		return
	var player_id := str(_auth_gateway.call("current_player").get("id", ""))
	if not _is_player_id(player_id):
		return
	var player_events: Array = _pending_by_player.get(player_id, [])
	if milestone_id in player_events:
		return
	player_events.append(milestone_id)
	_pending_by_player[player_id] = player_events
	_save_pending()
	_retry_after_msec = 0
	_flush_next()


func _on_authentication_changed(authenticated: bool, player: Dictionary) -> void:
	_active_player_id = str(player.get("id", "")) if authenticated else ""
	if not _is_player_id(_active_player_id):
		_active_player_id = ""
	_retry_after_msec = 0
	_flush_next()


func _flush_next() -> void:
	if _http == null or not _inflight_milestone.is_empty() or _active_player_id.is_empty():
		return
	if _auth_gateway == null or not bool(_auth_gateway.call("is_authenticated")) or str(_auth_gateway.call("current_player").get("id", "")) != _active_player_id:
		return
	var queued: Array = _pending_by_player.get(_active_player_id, [])
	if queued.is_empty():
		return
	if not bool(_auth_gateway.call("access_token_ready_for_connection")):
		_retry_after_msec = Time.get_ticks_msec() + 1000
		return
	_inflight_player_id = _active_player_id
	_inflight_milestone = str(queued[0])
	var headers := PackedStringArray([
		"Authorization: Bearer " + str(_auth_gateway.call("access_token_for_request")),
		"Content-Type: application/json"
	])
	var error := _http.request(
		str(_auth_gateway.get("api_base_url")) + ENDPOINT,
		headers,
		HTTPClient.METHOD_POST,
		JSON.stringify({"milestoneId": _inflight_milestone})
	)
	if error != OK:
		_schedule_retry()


func _on_request_completed(result: int, response_code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
	var response: Variant = JSON.parse_string(body.get_string_from_utf8())
	var accepted := result == HTTPRequest.RESULT_SUCCESS and response_code == 200 \
		and response is Dictionary and str(response.get("milestoneId", "")) == _inflight_milestone
	if accepted:
		var queued: Array = _pending_by_player.get(_inflight_player_id, [])
		queued.erase(_inflight_milestone)
		if queued.is_empty():
			_pending_by_player.erase(_inflight_player_id)
		else:
			_pending_by_player[_inflight_player_id] = queued
		_save_pending()
	_inflight_player_id = ""
	_inflight_milestone = ""
	if accepted:
		_retry_after_msec = 0
		_flush_next()
	else:
		_schedule_retry()


func _schedule_retry() -> void:
	_inflight_player_id = ""
	_inflight_milestone = ""
	_retry_after_msec = Time.get_ticks_msec() + RETRY_DELAY_MSEC


func _load_pending() -> void:
	if not FileAccess.file_exists(QUEUE_PATH):
		return
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(QUEUE_PATH))
	if not parsed is Dictionary:
		return
	for player_id in parsed:
		if not _is_player_id(str(player_id)) or not parsed[player_id] is Array:
			continue
		var valid: Array[String] = []
		for candidate in parsed[player_id]:
			var milestone_id := str(candidate)
			if is_milestone_id_valid(milestone_id) and milestone_id not in valid:
				valid.append(milestone_id)
		if not valid.is_empty():
			_pending_by_player[str(player_id)] = valid


func _save_pending() -> void:
	var file := FileAccess.open(QUEUE_PATH, FileAccess.WRITE)
	if file == null:
		push_warning("[StoryTelemetry] Could not persist the milestone retry queue.")
		return
	file.store_string(JSON.stringify(_pending_by_player))
	file.close()


func _is_player_id(value: String) -> bool:
	var pattern := RegEx.new()
	pattern.compile("^[0-9a-fA-F-]{36}$")
	return pattern.search(value) != null
