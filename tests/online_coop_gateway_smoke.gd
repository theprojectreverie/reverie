extends SceneTree

var _persistent_disconnect_count := 0

func _initialize() -> void:
	call_deferred("_run")

func _on_persistent_world_disconnected() -> void:
	_persistent_disconnect_count += 1

func _run() -> void:
	assert(root.has_node("CoopGateway"), "Co-op gateway autoload missing")
	var gateway := root.get_node("CoopGateway")
	assert(gateway.has_method("create_lobby"), "Create lobby request missing")
	assert(gateway.has_method("join_lobby"), "Join lobby request missing")
	assert(gateway.has_method("fetch_current_lobby"), "Current lobby request missing")
	assert(gateway.has_method("leave_lobby"), "Leave lobby request missing")
	var transport := root.get_node("MultiplayerGateway")
	transport.persistent_world_disconnected.connect(_on_persistent_world_disconnected)
	transport.disconnect_from_persistent_world()
	assert(_persistent_disconnect_count == 0, "Resetting an unused persistent-world transport must not emit a false disconnect event")
	transport._world_server_id = "00000000-0000-4000-8000-000000000001"
	transport.disconnect_from_persistent_world()
	assert(_persistent_disconnect_count == 1, "Disconnecting an existing persistent-world session must emit its lifecycle signal")
	assert(transport.has_method("_handle_session_revoked"), "Revoked realtime sessions must stop reconnecting")
	var auth := root.get_node("AuthGateway")
	assert(auth.has_method("invalidate_session"), "Revoked sessions must clear local credentials")
	transport._reconnect_enabled = true
	transport._lobby_id = "revoked-lobby"
	transport._world_server_id = "revoked-world"
	transport._world_ticket = "ephemeral-ticket"
	transport._world_ready = true
	transport._world_heartbeat_pending = true
	transport._handle_session_revoked()
	assert(not transport._reconnect_enabled and transport._lobby_id.is_empty(), "Revoked sessions must stop reconnecting to the old lobby")
	assert(transport._world_server_id.is_empty() and transport._world_ticket.is_empty() and not transport._world_ready, "Revoked sessions must clear persistent-world connection state")
	assert(not transport._world_heartbeat_pending, "Revoked sessions must clear persistent-world heartbeat state")
	assert(not auth.is_authenticated(), "Revoked sessions must clear the local access token")
	assert(gateway.has_signal("lobby_result"), "Lobby result signal missing")
	print("[online_coop_gateway_smoke] PASS")
	quit()
