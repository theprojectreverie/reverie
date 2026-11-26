extends Control
## Node-authored co-op lobby UI. The API remains the source of truth for membership.
signal closed

var _lobby_id := ""
var _region_id := ""
var _invite_code := ""
var _members: Array = []
var _max_members := 4
var _request_pending := false
var _refresh_queued := false
var _snapshot_verified := false
var _local_player_id := ""
@onready var content: VBoxContainer = $Center/Panel/Margins/Content
const SERVER_BROWSER_SCENE: PackedScene = preload("res://scenes/online/server_browser_screen.tscn")

@onready var status_label: Label = $Center/Panel/Margins/Content/Status
@onready var invite_input: LineEdit = $Center/Panel/Margins/Content/InviteCode
@onready var invite_display: Label = $Center/Panel/Margins/Content/InviteDisplay
@onready var members_label: Label = $Center/Panel/Margins/Content/Members
var expeditions: Dictionary = {}
@onready var region_input: OptionButton = $Center/Panel/Margins/Content/Region

func _ready() -> void:
	expeditions = JSON.parse_string(FileAccess.get_file_as_string("res://resources/data/six_zone_expeditions.json"))
	for id in expeditions:
		region_input.add_item(str(expeditions[id]["label"]))
		region_input.set_item_metadata(region_input.item_count - 1, id)
	region_input.select(0)
	$Center/Panel/Margins/Content/EnterButton.pressed.connect(_enter_expedition)
	UIFactory.set_full_rect(self)
	$Center/Panel/Margins/Content/Header/CloseButton.pressed.connect(closed.emit)
	$Center/Panel/Margins/Content/CreateButton.pressed.connect(_create_lobby)
	$Center/Panel/Margins/Content/JoinButton.pressed.connect(_join_lobby)
	$Center/Panel/Margins/Content/Actions/RefreshButton.pressed.connect(_refresh_lobby)
	$Center/Panel/Margins/Content/Actions/LeaveButton.pressed.connect(_leave_lobby)
	$Center/Panel/Margins/Content/Actions/CopyInviteButton.pressed.connect(_copy_invite)
	invite_input.text_changed.connect(func(_value: String): _update_controls())
	invite_input.text_submitted.connect(func(_value: String):
		if not content.get_node("JoinButton").disabled: _join_lobby()
	)
	$Center/Panel/Margins/Content/ServerBrowserButton.pressed.connect(_open_server_browser)
	CoopGateway.lobby_result.connect(_on_lobby_result)
	MultiplayerGateway.lobby_connected.connect(_on_realtime_connected)
	MultiplayerGateway.lobby_disconnected.connect(_on_realtime_disconnected)
	MultiplayerGateway.connection_failed.connect(_on_realtime_failed)
	MultiplayerGateway.server_event.connect(_on_server_event)
	_refresh_lobby()

func _exit_tree() -> void:
	if CoopGateway.lobby_result.is_connected(_on_lobby_result):
		CoopGateway.lobby_result.disconnect(_on_lobby_result)
	if MultiplayerGateway.lobby_connected.is_connected(_on_realtime_connected):
		MultiplayerGateway.lobby_connected.disconnect(_on_realtime_connected)
	if MultiplayerGateway.lobby_disconnected.is_connected(_on_realtime_disconnected):
		MultiplayerGateway.lobby_disconnected.disconnect(_on_realtime_disconnected)
	if MultiplayerGateway.connection_failed.is_connected(_on_realtime_failed):
		MultiplayerGateway.connection_failed.disconnect(_on_realtime_failed)
	if MultiplayerGateway.server_event.is_connected(_on_server_event):
		MultiplayerGateway.server_event.disconnect(_on_server_event)

func _open_server_browser() -> void:
	var browser := SERVER_BROWSER_SCENE.instantiate()
	add_child(browser)
	browser.closed.connect(browser.queue_free)

func _update_controls() -> void:
	var has_lobby := not _lobby_id.is_empty()
	content.get_node("CreateButton").disabled = _request_pending or has_lobby
	region_input.disabled = _request_pending or has_lobby
	invite_input.editable = not _request_pending and not has_lobby
	content.get_node("JoinButton").disabled = _request_pending or has_lobby or invite_input.text.strip_edges().length() < 20
	content.get_node("Actions/RefreshButton").disabled = _request_pending
	content.get_node("Actions/LeaveButton").disabled = _request_pending or not has_lobby
	content.get_node("Actions/CopyInviteButton").disabled = _invite_code.is_empty() or not has_lobby
	content.get_node("EnterButton").disabled = _request_pending or not has_lobby or not _snapshot_verified or not MultiplayerGateway.is_connected_to_lobby() or not expeditions.has(_region_id)
	if has_lobby:
		for i in region_input.item_count:
			if str(region_input.get_item_metadata(i)) == _region_id:
				region_input.select(i)
				break

func _copy_invite() -> void:
	if not _invite_code.is_empty() and not _lobby_id.is_empty():
		DisplayServer.clipboard_set(_invite_code)
		status_label.text = "Invite code copied."

func _create_lobby() -> void:
	if _request_pending or not _lobby_id.is_empty():
		return
	status_label.text = "Creating your expedition…"
	var region_id := str(region_input.get_item_metadata(region_input.selected))
	if region_id.is_empty():
		region_id = "six_zone_royal_gardens"
	var result := CoopGateway.create_lobby(region_id, 4)
	_request_pending = result == OK
	if result != OK:
		status_label.text = "Could not start lobby creation. Check your connection."
	_update_controls()

func _join_lobby() -> void:
	if _request_pending or not _lobby_id.is_empty():
		return
	status_label.text = "Joining expedition…"
	var result := CoopGateway.join_lobby(invite_input.text)
	_request_pending = result == OK
	if result != OK:
		status_label.text = "Enter a valid invite code first."
	_update_controls()

func _refresh_lobby() -> void:
	if _request_pending:
		_refresh_queued = true
		return
	status_label.text = "Checking your current expedition…"
	var result := CoopGateway.fetch_current_lobby()
	_request_pending = result == OK
	if result != OK:
		status_label.text = "Unable to refresh your lobby right now."
	_update_controls()

func _leave_lobby() -> void:
	if _lobby_id.is_empty():
		status_label.text = "You are not in an expedition."
		return
	if _request_pending:
		return
	status_label.text = "Leaving expedition…"
	var result := CoopGateway.leave_lobby(_lobby_id)
	_request_pending = result == OK
	if result != OK:
		status_label.text = "Could not send the leave request."
	_update_controls()

func _on_lobby_result(operation: String, success: bool, payload: Dictionary) -> void:
	_request_pending = false
	if _refresh_queued:
		_refresh_queued = false
		_refresh_lobby.call_deferred()
	if not success:
		status_label.text = _friendly_error(str(payload.get("error", "request_failed")))
		_update_controls()
		return
	match operation:
		"create":
			_lobby_id = str(payload.get("lobbyId", ""))
			_region_id = str(payload.get("regionId", ""))
			_invite_code = str(payload.get("inviteCode", ""))
			invite_display.text = "Invite code: " + _invite_code
			status_label.text = "Expedition created. Share the invite code with your friends."
			_connect_realtime()
			call_deferred("_refresh_lobby")
		"join":
			_lobby_id = str(payload.get("lobbyId", ""))
			_region_id = str(payload.get("regionId", ""))
			_invite_code = ""
			invite_display.text = "Joined an expedition."
			status_label.text = "You joined the expedition."
			_connect_realtime()
			call_deferred("_refresh_lobby")
		"current":
			var lobby: Variant = payload.get("lobby", null)
			if lobby == null or typeof(lobby) != TYPE_DICTIONARY or (lobby as Dictionary).is_empty():
				_lobby_id = ""
				_region_id = ""
				_invite_code = ""
				_snapshot_verified = false
				MultiplayerGateway.disconnect_from_lobby()
				_members.clear()
				members_label.text = "No active expedition yet."
				invite_display.text = "Create a lobby or join with an invite code."
				status_label.text = "Ready to explore with friends."
			else:
				var data: Dictionary = lobby
				var new_lobby_id := str(data.get("id", ""))
				if new_lobby_id != _lobby_id:
					_invite_code = ""
					invite_display.text = "You are in an existing expedition."
					_snapshot_verified = false
				_lobby_id = new_lobby_id
				_max_members = int(data.get("maxMembers", 4))
				_region_id = str(data.get("regionId", ""))
				_members = data.get("members", [])
				_render_members()
				status_label.text = "Expedition found. Connecting to its shared session…"
				if MultiplayerGateway.is_connected_to_lobby() and MultiplayerGateway._lobby_id == _lobby_id and _snapshot_verified:
					status_label.text = "Party synchronized. Ready to enter."
				elif not MultiplayerGateway._connection_pending and not _lobby_id.is_empty():
					_connect_realtime()
		"leave":
			MultiplayerGateway.disconnect_from_lobby()
			_snapshot_verified = false
			_lobby_id = ""
			_region_id = ""
			_invite_code = ""
			_members.clear()
			invite_display.text = "No active invite."
			members_label.text = "No active expedition yet."
			status_label.text = "You left the expedition."
	_update_controls()

func _connect_realtime() -> void:
	if _lobby_id.is_empty():
		status_label.text = "The server did not return a lobby ID."
		return
	_snapshot_verified = false
	_local_player_id = ""
	var result := MultiplayerGateway.connect_to_lobby(_lobby_id)
	if result != OK:
		status_label.text = "Could not start the shared world connection."

func _on_realtime_connected(_lobby_id_value: String) -> void:
	status_label.text = "Connected. Synchronizing your expedition..."
	_update_controls()

func _on_realtime_disconnected() -> void:
	if is_inside_tree():
		_snapshot_verified = false
		status_label.text = "Disconnected from the shared world."
		_update_controls()

func _on_realtime_failed(reason: String) -> void:
	_snapshot_verified = false
	status_label.text = "Shared world connection failed: " + reason
	_update_controls()

func _on_server_event(payload: Dictionary) -> void:
	var event_type := str(payload.get("type", ""))
	if event_type == "connected":
		_local_player_id = str(payload.get("playerId", ""))
		return
	if event_type == "snapshot":
		_members = payload.get("members", [])
		if not _members.is_empty() and _members[0] is Dictionary:
			_region_id = str(_members[0].get("region_id", _region_id))
		_snapshot_verified = not _local_player_id.is_empty() and _members.any(func(member): return member is Dictionary and str(member.get("id", "")) == _local_player_id) and expeditions.has(_region_id)
		status_label.text = "Party synchronized. Ready to enter." if _snapshot_verified else "Party synchronization incomplete. Refresh to retry."
		_render_members()
		_update_controls()
	elif event_type == "region_transition":
		_region_id = str(payload.get("regionId", _region_id))
		_render_members()
		_update_controls()
	elif event_type == "player_joined" or event_type == "player_left":
		_refresh_lobby()

func _render_members() -> void:
	if _members.is_empty():
		members_label.text = "No member details received yet."
		return
	var lines: PackedStringArray = []
	for member in _members:
		if typeof(member) != TYPE_DICTIONARY:
			continue
		var entry: Dictionary = member
		var role := "Leader" if str(entry.get("role", "")) == "leader" else "Member"
		lines.append("%s  ·  Lv. %s  ·  %s" % [
			str(entry.get("name", "Wanderer")),
			str(entry.get("level", "1")),
			role
		])
	members_label.text = "%s | PARTY %d/%d\n" % [str(expeditions.get(_region_id, {}).get("label", "Expedition")), lines.size(), _max_members] + "\n".join(lines)

func _friendly_error(code: String) -> String:
	match code:
		"already_in_lobby", "already_in_another_lobby":
			return "You are already in an expedition. Refresh your lobby."
		"lobby_full":
			return "This expedition is full."
		"lobby_unavailable":
			return "That invite is invalid or the expedition has closed."
		"blocked_player_in_lobby":
			return "You cannot join this expedition because of its member settings."
		"authentication_required":
			return "Your session expired. Sign in again."
		_:
			return "Expedition request failed: " + code

func _enter_expedition() -> void:
	if _request_pending or not _snapshot_verified or not MultiplayerGateway.is_connected_to_lobby() or not expeditions.has(_region_id) or _lobby_id.is_empty():
		status_label.text = "Join a connected expedition first."
		return
	if not bool(GameState.quest_domain.flags.get("tutorial_complete", false)):
		status_label.text = "Complete the tutorial before entering a shared expedition."
		return
	MultiplayerGateway.standalone_expedition_id = _lobby_id
	MultiplayerGateway.standalone_expedition_region = _region_id
	get_tree().change_scene_to_file(str(expeditions[_region_id]["scene"]))