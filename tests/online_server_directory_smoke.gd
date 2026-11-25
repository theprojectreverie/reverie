extends SceneTree

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var gateway := root.get_node_or_null("ServerDirectoryGateway")
	assert(gateway != null, "Persistent server directory gateway must be autoloaded")
	assert(gateway.has_method("list_servers"), "Server discovery request missing")
	assert(gateway.has_method("join_server"), "Persistent server assignment request missing")
	assert(gateway.has_method("reconnect_server"), "Persistent server reconnect-ticket request missing")
	assert(gateway.has_method("leave_server"), "Persistent server leave request missing")
	assert(gateway.has_signal("server_list_received"), "Server list signal missing")
	assert(gateway.has_signal("assignment_received"), "Server assignment signal missing")
	assert(gateway.has_signal("request_failed"), "Directory error signal missing")
	assert(gateway.get_node_or_null("HTTPRequest") != null, "Directory HTTP transport missing")
	assert(root.has_node("AuthGateway"), "Auth gateway must initialize before server directory")
	print("[online_server_directory_smoke] PASS")
	quit()
