extends SceneTree

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	assert(root.has_node("AuthGateway"), "Authentication gateway autoload missing")
	var auth: Node = root.get_node("AuthGateway")
	assert(auth.call("seconds_until_access_expiry") == 0.0, "Unauthenticated client should not retain an access-token expiry")
	assert(auth.call("register_account", "bad-email", "short", "bad name") == ERR_INVALID_PARAMETER, "Registration should reject invalid input before network access")
	assert(auth.call("login", "", "") == ERR_INVALID_PARAMETER, "Login should reject empty credentials before network access")
	assert(auth.call("verify_email", "short") == ERR_INVALID_PARAMETER, "Verification should reject malformed tokens before network access")
	assert(auth.call("logout_all_sessions") == ERR_UNAUTHORIZED, "Account-wide logout should require an authenticated session")
	assert(auth.get_node_or_null("LogoutAllRequest") != null, "Account-wide logout request node missing")
	var packed := load("res://scenes/online/account_screen.tscn") as PackedScene
	assert(packed != null, "Account screen scene must load")
	var instance := packed.instantiate()
	root.add_child(instance)
	await process_frame
	assert(instance.get_node_or_null("Center/Panel/Margins/Content/Tabs/SignIn/LoginButton") != null, "Login button missing")
	assert(instance.get_node_or_null("Center/Panel/Margins/Content/Tabs/CreateAccount/RegisterButton") != null, "Register button missing")
	assert(instance.get_node_or_null("Center/Panel/Margins/Content/Tabs/CreateAccount/VerifyButton") != null, "Verify button missing")
	instance.queue_free()
	await process_frame
	print("[online_auth_scene_smoke] PASS")
	quit()
