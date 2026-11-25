extends Control
## Persistent regional server directory UI. Assignment is not a world connection.
signal closed

@onready var status_label: Label = $Center/Panel/Margins/Content/Status
@onready var server_list: VBoxContainer = $Center/Panel/Margins/Content/Scroll/ServerList
@onready var refresh_button: Button = $Center/Panel/Margins/Content/Actions/RefreshButton

var _servers: Array = []
var _busy := false
var _current_server_id := ""
var _reconnect_attempts := 0
const MAX_WORLD_RECONNECT_ATTEMPTS := 2

func _ready() -> void:
	UIFactory.set_full_rect(self)
	$Center/Panel/Margins/Content/Header/CloseButton.pressed.connect(closed.emit)
	refresh_button.pressed.connect(_refresh)
	ServerDirectoryGateway.server_list_received.connect(_on_servers_received)
	ServerDirectoryGateway.assignment_received.connect(_on_assignment_received)
	ServerDirectoryGateway.request_failed.connect(_on_request_failed)
	MultiplayerGateway.persistent_world_connected.connect(_on_world_connected)
	MultiplayerGateway.persistent_world_connection_failed.connect(_on_world_connection_failed)
	_refresh()

func _exit_tree() -> void:
	if ServerDirectoryGateway.server_list_received.is_connected(_on_servers_received):
		ServerDirectoryGateway.server_list_received.disconnect(_on_servers_received)
	if ServerDirectoryGateway.assignment_received.is_connected(_on_assignment_received):
		ServerDirectoryGateway.assignment_received.disconnect(_on_assignment_received)
	if ServerDirectoryGateway.request_failed.is_connected(_on_request_failed):
		ServerDirectoryGateway.request_failed.disconnect(_on_request_failed)
	if MultiplayerGateway.persistent_world_connected.is_connected(_on_world_connected):
		MultiplayerGateway.persistent_world_connected.disconnect(_on_world_connected)
	if MultiplayerGateway.persistent_world_connection_failed.is_connected(_on_world_connection_failed):
		MultiplayerGateway.persistent_world_connection_failed.disconnect(_on_world_connection_failed)

func _refresh() -> void:
	if _busy:
		return
	_busy = true
	refresh_button.disabled = true
	status_label.text = "Searching for active regional worlds…"
	var result: Error = ServerDirectoryGateway.list_servers()
	if result != OK:
		_busy = false
		refresh_button.disabled = false
		status_label.text = "Sign in first, or wait for the current request to finish."

func _on_servers_received(servers: Array) -> void:
	_busy = false
	refresh_button.disabled = false
	_servers = servers
	for child in server_list.get_children():
		child.queue_free()
	if _servers.is_empty():
		status_label.text = "No persistent worlds are online right now. The directory is reachable, but a dedicated world process must be running before a region appears here."
		return
	status_label.text = "Choose a regional world to connect to its persistent session."
	for item in _servers:
		if typeof(item) != TYPE_DICTIONARY:
			continue
		var server: Dictionary = item
		var server_id := str(server.get("id", ""))
		var name := str(server.get("display_name", server.get("displayName", "Regional World")))
		var region := str(server.get("region_id", server.get("regionId", "unknown")))
		var current := int(server.get("current_players", server.get("currentPlayers", 0)))
		var maximum := int(server.get("max_players", server.get("maxPlayers", 0)))
		var row := HBoxContainer.new()
		var details := Label.new()
		details.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		details.text = "%s  ·  %s  ·  %d/%d" % [name, region, current, maximum]
		row.add_child(details)
		var join := Button.new()
		var has_transport := str(server.get("endpoint_url", server.get("endpointUrl", ""))).begins_with("ws")
		join.text = "JOIN" if has_transport else "OFFLINE"
		join.disabled = not _is_uuid(server_id) or _busy or not has_transport
		if has_transport:
			join.pressed.connect(_join.bind(server_id))
		row.add_child(join)
		server_list.add_child(row)

func _join(server_id: String) -> void:
	if _busy:
		return
	_busy = true
	refresh_button.disabled = true
	status_label.text = "Requesting a place in the selected world…"
	var result: Error = ServerDirectoryGateway.join_server(server_id)
	if result != OK:
		_busy = false
		refresh_button.disabled = false
		status_label.text = "Could not start the assignment request."

func _on_assignment_received(payload: Dictionary) -> void:
	_busy = false
	refresh_button.disabled = false
	if str(payload.get("status", "")) == "left":
		_current_server_id = ""
		_reconnect_attempts = 0
		ServerDirectoryGateway.clear_pending_join_ticket()
		status_label.text = "Your server assignment has been released."
	elif not ServerDirectoryGateway.pending_join_ticket.is_empty():
		var server_id := str(payload.get("serverId", ""))
		_current_server_id = server_id
		var ticket := ServerDirectoryGateway.pending_join_ticket
		var endpoint := ServerDirectoryGateway.pending_world_endpoint
		var expiry_text := ServerDirectoryGateway.pending_join_ticket_expires_at
		var expiry_unix := Time.get_unix_time_from_datetime_string(expiry_text) if not expiry_text.is_empty() else 0
		if expiry_unix <= int(Time.get_unix_time_from_system()):
			ServerDirectoryGateway.clear_pending_join_ticket()
			status_label.text = "The join ticket expired before connection. Refresh the directory and try again."
			return
		var connect_result := MultiplayerGateway.connect_to_persistent_world(server_id, ticket, endpoint)
		ServerDirectoryGateway.clear_pending_join_ticket()
		if connect_result == OK:
			status_label.text = "Connecting to the selected persistent world…"
		else:
			status_label.text = "The world slot is reserved, but the live connection could not start. You can leave this server and try again."
	else:
		status_label.text = "Assignment response received, but no usable connection ticket was returned."

func _on_world_connected(server_id: String) -> void:
	_current_server_id = server_id
	_reconnect_attempts = 0
	status_label.text = "Connected to persistent world %s. Your session is live." % server_id

func _on_world_connection_failed(reason: String) -> void:
	if _current_server_id.is_empty() or _busy or _reconnect_attempts >= MAX_WORLD_RECONNECT_ATTEMPTS:
		status_label.text = "World connection failed: %s" % reason
		return
	_reconnect_attempts += 1
	_busy = true
	refresh_button.disabled = true
	status_label.text = "Connection interrupted. Restoring your place in the world (%d/%d)…" % [_reconnect_attempts, MAX_WORLD_RECONNECT_ATTEMPTS]
	var result := ServerDirectoryGateway.reconnect_server(_current_server_id)
	if result != OK:
		_busy = false
		refresh_button.disabled = false
		status_label.text = "Could not request world reconnection. Your server reservation may have expired."


func _on_request_failed(operation: String, reason: String) -> void:
	_busy = false
	refresh_button.disabled = false
	status_label.text = "%s failed: %s" % [operation.capitalize(), reason]

func _is_uuid(value: String) -> bool:
	var regex := RegEx.new()
	regex.compile("^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$")
	return regex.search(value) != null
