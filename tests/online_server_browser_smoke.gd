extends SceneTree

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var packed: PackedScene = load("res://scenes/online/server_browser_screen.tscn")
	assert(packed != null, "Persistent world browser scene must load")
	var browser: Control = packed.instantiate()
	root.add_child(browser)
	await process_frame
	assert(browser.get_node_or_null("Center/Panel/Margins/Content/Scroll/ServerList") != null, "Server list container missing")
	assert(browser.get_node_or_null("Center/Panel/Margins/Content/Status") != null, "Directory status missing")
	assert(browser.get_node_or_null("Center/Panel/Margins/Content/Actions/RefreshButton") != null, "Refresh control missing")
	assert(browser.has_signal("closed"), "Browser close signal missing")
	var fallback: CheckButton = browser.get_node("Center/Panel/Margins/Content/RegionFallback")
	assert(not fallback.button_pressed, "Fallback must require explicit opt-in")
	fallback.button_pressed = true
	assert(fallback.button_pressed)
	browser._on_request_failed("join", "region_full")
	assert("full" in browser.status_label.text)

	var lobby_script := load("res://scripts/online/coop_lobby_screen.gd")
	assert(lobby_script != null, "Co-op lobby integration script must load")
	browser.queue_free()
	print("[online_server_browser_smoke] PASS")
	quit()
