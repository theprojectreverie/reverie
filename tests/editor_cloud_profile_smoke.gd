extends SceneTree

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var profile = load("res://scripts/online/connection_profile.gd")
	var cloud := "--reverie-cloud" in OS.get_cmdline_user_args() and not "--reverie-local" in OS.get_cmdline_user_args() and OS.get_environment("REVERIE_LOCAL_DEV") != "1"
	var expected: String = profile.PUBLIC_ORIGIN if cloud else profile.LOCAL_ORIGIN
	var expected_ws: String = expected.replace("https://", "wss://").replace("http://", "ws://") + "/v1/realtime"
	var expected_save := "user://reverie_cloud_editor_save.json" if cloud else "user://project_fantasy_save.json"
	var expected_session := "user://remembered_cloud_editor_session_v2.dpapi" if cloud else "user://remembered_session_v2.dpapi"
	var auth = root.get_node("AuthGateway")
	var multi = root.get_node("MultiplayerGateway")
	var save = root.get_node("SaveService")
	var ok = profile.is_public_alpha() == cloud and auth.api_base_url == expected and multi.websocket_url == expected_ws
	ok = ok and root.get_node("CoopGateway").api_base_url == expected and root.get_node("PvpGateway").api_base_url == expected and root.get_node("ServerDirectoryGateway").api_base_url == expected
	ok = ok and profile.persistent_world_enabled(cloud) != cloud and (not cloud or multi.persistent_world_websocket_url.is_empty())
	ok = ok and save.SAVE_PATH == expected_save and auth._session_path() == expected_session
	print("EDITOR_CLOUD_PROFILE ", "PASS" if ok else "FAIL", " cloud=",cloud," api=",auth.api_base_url," save=",save.SAVE_PATH)
	quit(0 if ok else 1)
