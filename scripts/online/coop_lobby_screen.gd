extends Control
## Node-authored co-op lobby UI. The API remains the source of truth for membership.
signal closed

var _lobby_id := ""
var _invite_code := ""
var _members: Array = []
const SERVER_BROWSER_SCENE: PackedScene = preload("res://scenes/online/server_browser_screen.tscn")

@onready var status_label: Label = $Center/Panel/Margins/Content/Status
@onready var invite_input: LineEdit = $Center/Panel/Margins/Content/InviteCode
@onready var invite_display: Label = $Center/Panel/Margins/Content/InviteDisplay
@onready var members_label: Label = $Center/Panel/Margins/Content/Members
@onready var region_input: LineEdit = $Center/Panel/Margins/Content/Region

func _ready() -> void:
	UIFactory.set_full_rect(self)
	$Center/Panel/Margins/Content/Header/CloseButton.pressed.connect(closed.emit)
	$Center/Panel/Margins/Content/CreateButton.pressed.connect(_create_lobby)
	$Center/Panel/Margins/Content/JoinButton.pressed.connect(_join_lobby)
	$Center/Panel/Margins/Content/Actions/RefreshButton.pressed.connect(_refresh_lobby)
	$Center/Panel/Margins/Content/Actions/LeaveButton.pressed.connect(_leave_lobby)
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

func _create_lobby() -> void:
	status_label.text = "Creating your expedition…"
	var region_id := region_input.text.strip_edges().to_lower()
	if region_id.is_empty():
		region_id = "royal_gardens"
	var result := CoopGateway.create_lobby(region_id, 4)
	if result != OK:
		status_label.text = "Could not start lobby creation. Check your connection."

func _join_lobby() -> void:
	status_label.text = "Joining expedition…"
	var result := CoopGateway.join_lobby(invite_input.text)
	if result != OK:
		status_label.text = "Enter a valid invite code first."

func _refresh_lobby() -> void:
	status_label.text = "Checking your current expedition…"
	var result := CoopGateway.fetch_current_lobby()
	if result != OK:
		status_label.text = "Unable to refresh your lobby right now."

func _leave_lobby() -> void:
	if _lobby_id.is_empty():
		status_label.text = "You are not in an expedition."
		return
	MultiplayerGateway.disconnect_from_lobby()
	status_label.text = "Leaving expedition…"
	var result := CoopGateway.leave_lobby(_lobby_id)
	if result != OK:
		status_label.text = "Could not send the leave request."

func _on_lobby_result(operation: String, success: bool, payload: Dictionary) -> void:
	if not success:
		status_label.text = _friendly_error(str(payload.get("error", "request_failed")))
		return
	match operation:
		"create":
			_lobby_id = str(payload.get("lobbyId", ""))
			_invite_code = str(payload.get("inviteCode", ""))
			invite_display.text = "Invite code: " + _invite_code
			status_label.text = "Expedition created. Share the invite code with your friends."
			_connect_realtime()
			call_deferred("_refresh_lobby")
		"join":
			_lobby_id = str(payload.get("lobbyId", ""))
			_invite_code = ""
			invite_display.text = "Joined an expedition."
			status_label.text = "You joined the expedition."
			_connect_realtime()
			call_deferred("_refresh_lobby")
		"current":
			var lobby: Variant = payload.get("lobby", null)
			if lobby == null or typeof(lobby) != TYPE_DICTIONARY or (lobby as Dictionary).is_empty():
				_lobby_id = ""
				_members.clear()
				members_label.text = "No active expedition yet."
				invite_display.text = "Create a lobby or join with an invite code."
				status_label.text = "Ready to explore with friends."
			else:
				var data: Dictionary = lobby
				_lobby_id = str(data.get("id", ""))
				_members = data.get("members", [])
				_render_members()
				status_label.text = "Expedition found. Connecting to its shared session…"
				if not MultiplayerGateway.is_connected_to_lobby() and not _lobby_id.is_empty():
					_connect_realtime()
		"leave":
			_lobby_id = ""
			_invite_code = ""
			_members.clear()
			invite_display.text = "No active invite."
			members_label.text = "No active expedition yet."
			status_label.text = "You left the expedition."

func _connect_realtime() -> void:
	if _lobby_id.is_empty():
		status_label.text = "The server did not return a lobby ID."
		return
	var result := MultiplayerGateway.connect_to_lobby(_lobby_id)
	if result != OK:
		status_label.text = "Could not start the shared world connection."

func _on_realtime_connected(_lobby_id_value: String) -> void:
	status_label.text = "Connected to the shared expedition."

func _on_realtime_disconnected() -> void:
	if is_inside_tree():
		status_label.text = "Disconnected from the shared world."

func _on_realtime_failed(reason: String) -> void:
	status_label.text = "Shared world connection failed: " + reason

func _on_server_event(payload: Dictionary) -> void:
	var event_type := str(payload.get("type", ""))
	if event_type == "snapshot":
		_members = payload.get("members", [])
		_render_members()
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
	members_label.text = "EXPEDITION PARTY\n" + "\n".join(lines)

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
