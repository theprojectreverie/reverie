extends Node
## World sprites display per-account server cooldowns; world attacks open the
## existing authoritative turn-based HUD. No client-supplied damage is sent.
const GROUPS := ["rose_slime_garden_1", "rose_slime_garden_2", "rose_slime_garden_3", "rose_slime_garden_4", "rose_slime_garden_5", "rose_slime_garden_6", "crownling_garden_1", "crownling_garden_2", "crownling_garden_3"]
var _zone: Node2D
var _world: Node
var _player: Player
var _owner := ""
var _http: HTTPRequest
var _pending := false
var _fresh := false
var _next_poll := 0
var _active_group := ""
var _monsters: Dictionary = {}
var _remaining: Dictionary = {}
var _opened := false

func bind(zone: Node2D, world: Node, player: Player) -> void:
	_zone = zone
	_world = world
	_player = player
	_owner = str(AuthGateway.current_player().get("id", ""))
	for node in zone.get_tree().get_nodes_in_group("world_action_targets"):
		if zone.is_ancestor_of(node) and str(node.get("group_id")) in GROUPS:
			_monsters[str(node.group_id)] = node
	_http = HTTPRequest.new()
	_http.timeout = 8.0
	add_child(_http)
	_http.request_completed.connect(_on_status)
	world.status_changed.connect(_on_connection)
	EventBus.battle_finished.connect(_on_battle_finished)
	_next_poll = Time.get_ticks_msec()

func _process(_delta: float) -> void:
	if not is_instance_valid(_world) or not _world.is_story_ready():
		_fresh = false
		return
	if _opened or _pending or Time.get_ticks_msec() < _next_poll or not AuthGateway.access_token_ready_for_connection():return
	_next_poll = Time.get_ticks_msec()+2000
	_pending = true
	var error := _http.request(AuthGateway.api_base_url+"/v1/gardens-story/",PackedStringArray(["Authorization: Bearer "+AuthGateway.access_token_for_request(),"Content-Type: application/json"]),HTTPClient.METHOD_POST,JSON.stringify({"operation":"status"}))
	if error != OK:
		_pending = false
		_fresh = false

func _on_connection(ready: bool, _reason: String) -> void:
	_fresh = false
	if _pending:
		_http.cancel_request()
		_pending = false
	if ready:_next_poll = 0

func _on_status(result: int, code: int, _headers: PackedStringArray, bytes: PackedByteArray) -> void:
	_pending = false
	var data: Variant = JSON.parse_string(bytes.get_string_from_utf8())
	if result != HTTPRequest.RESULT_SUCCESS or code != 200 or not data is Dictionary or not _world.is_story_ready() or str(AuthGateway.current_player().get("id", "")) != _owner or not apply_status(data,_owner):
		_fresh = false

func apply_status(data: Dictionary, owner: String) -> bool:
	if not data.get("ok",false) or str(data.get("playerId","")) != owner or not data.get("encounters") is Array or data.encounters.size()!=GROUPS.size():return false
	var next := {}
	for row in data.encounters:
		if not row is Dictionary:return false
		var group := str(row.get("groupId",""))
		var ms: Variant = row.get("remainingMs")
		if group not in GROUPS or next.has(group) or typeof(ms) not in [TYPE_FLOAT,TYPE_INT] or not is_finite(float(ms)) or float(ms)<0 or float(ms)>15000:return false
		next[group] = int(ms)
	var active: Variant = data.get("active")
	if active != null and (not active is Dictionary or str(active.get("groupId","")) not in GROUPS or str(active.get("battleId","" )).is_empty()):return false
	_remaining = next
	_active_group = str(active.groupId) if active is Dictionary else ""
	_fresh = true
	for group in GROUPS:
		var mob = _monsters.get(group)
		if is_instance_valid(mob):mob.apply_story_respawn_ms(next[group])
	return true

func request_encounter(group: String) -> bool:
	if not _fresh or _pending or _opened or group not in GROUPS or int(_remaining.get(group,-1)) != 0 or not _world.is_story_ready() or not _player.input_enabled or _player.network_recovery_paused:return false
	if not _active_group.is_empty() and _active_group != group:
		EventBus.toast_requested.emit("Finish your previous garden battle first.")
		return false
	var mob = _monsters.get(group)
	if not is_instance_valid(mob) or _player.global_position.distance_to(mob.global_position)>95.0:return false
	var router := _zone.get_node_or_null("CombatRouter") as GameCombatRouterComponent
	if router == null:return false
	_opened = true
	_player.input_enabled = false
	_player.velocity = Vector2.ZERO
	TouchInput.release()
	if not router.start_encounter(group):
		_opened = false
		_player.input_enabled = true
		return false
	router.combat_closed.connect(_on_closed,CONNECT_ONE_SHOT)
	return true

func _on_battle_finished(result: Dictionary) -> void:
	if str(result.get("group_id","")) in GROUPS:
		_fresh = false
		_next_poll = 0

func _on_closed() -> void:
	_opened = false
	_fresh = false
	_next_poll = 0
	if is_instance_valid(_player):_player.input_enabled = true
