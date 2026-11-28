extends Node
## Account-scoped read-only view of verified village progress.
const GROUPS := ["village_slime_1","village_slime_2","village_crimson_encounter","village_crownling_1","village_crownling_2","village_crownling_3","village_nyx_encounter","gerald_boss_encounter"]
const QUESTS := ["village_clear_approach","village_crimson_duel","village_clear_ruins","village_nyx_duel","village_gerald_trial"]
var _world: Node
var _owner := ""
var _http: HTTPRequest
var _fresh := false
var _pending := false
var _next := 0
var _wins: Array = []
var _quests: Dictionary = {}

func bind(world: Node) -> void:
	_world = world
	_owner = str(AuthGateway.current_player().get("id",""))
	_http = HTTPRequest.new()
	_http.timeout = 8
	add_child(_http)
	_http.request_completed.connect(_on_status)
	world.status_changed.connect(_on_connection)
	EventBus.battle_finished.connect(_on_battle_finished)

func _process(_delta: float) -> void:
	if not is_instance_valid(_world) or not _world.is_story_ready() or str(AuthGateway.current_player().get("id","")) != _owner:
		if _fresh:
			_fresh = false
			_notify()
		return
	if _pending or Time.get_ticks_msec() < _next or not AuthGateway.access_token_ready_for_connection():
		return
	_next = Time.get_ticks_msec() + 2000
	_pending = true
	var err := _http.request(AuthGateway.api_base_url + "/v1/village-story/", PackedStringArray(["Authorization: Bearer "+AuthGateway.access_token_for_request(),"Content-Type: application/json"]), HTTPClient.METHOD_POST, JSON.stringify({"operation":"status"}))
	if err != OK:
		_pending = false
		_fresh = false
		_notify()

func _on_connection(_ready: bool, _reason: String) -> void:
	_fresh = false
	_next = 0
	if _pending:
		_http.cancel_request()
		_pending = false
	_notify()

func _on_battle_finished(result: Dictionary) -> void:
	if str(result.get("group_id","")) in GROUPS:
		_fresh = false
		_next = 0
		_notify()

func _on_status(result: int, code: int, _headers: PackedStringArray, bytes: PackedByteArray) -> void:
	_pending = false
	var data: Variant = JSON.parse_string(bytes.get_string_from_utf8())
	if result != HTTPRequest.RESULT_SUCCESS or code != 200 or not data is Dictionary or not _world.is_story_ready() or str(AuthGateway.current_player().get("id","")) != _owner or not apply_status(data):
		_fresh = false
		_notify()

func apply_status(data: Dictionary) -> bool:
	if not data.get("ok",false) or str(data.get("playerId","")) != _owner or not data.get("wins") is Array or not data.get("quests") is Array or data.quests.size()!=QUESTS.size():
		return false
	var wins: Array = data.wins
	for group in wins:
		if group not in GROUPS:
			return false
	var quests := {}
	for row in data.quests:
		if not row is Dictionary or str(row.get("quest","")) not in QUESTS or str(row.get("state","")) not in ["active","complete","not_started"] or quests.has(row.quest):
			return false
		if typeof(row.get("progress")) not in [TYPE_FLOAT,TYPE_INT] or typeof(row.get("total")) not in [TYPE_FLOAT,TYPE_INT] or float(row.progress)<0 or float(row.progress)>float(row.total):
			return false
		quests[row.quest]=row.duplicate(true)
	var changed := not _fresh or quests != _quests or wins != _wins
	_wins=wins.duplicate()
	_quests=quests
	_fresh=true
	if changed:
		_notify()
	return true

func _notify() -> void:
	for quest in QUESTS:
		EventBus.quest_updated.emit(quest)
	EventBus.party_changed.emit()

func ready_for_group(group: String, quest: String) -> bool:
	return _fresh and group not in _wins and quest_state(quest) == "active"

func won(group: String) -> bool:
	return _fresh and group in _wins

func quest_state(id: String) -> String:
	return str(_quests.get(id,{}).get("state","not_started")) if _fresh else "not_started"

func quest_progress(id: String) -> int:
	return int(_quests.get(id,{}).get("progress",0)) if _fresh else 0

func active_quest() -> String:
	for q in QUESTS:
		if quest_state(q)=="active":
			return q
	return ""

func party_ids() -> Array:
	var ids: Array=["kael"]
	if won("village_crimson_encounter"):ids.append("crimson_witch_legendary")
	if won("village_nyx_encounter"):ids.append("nyx")
	return ids
