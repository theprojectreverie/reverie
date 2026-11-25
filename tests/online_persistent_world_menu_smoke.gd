extends SceneTree

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var packed := load("res://scenes/ui/main_menu.tscn") as PackedScene
	assert(packed != null, "Main menu scene must load")
	var menu := packed.instantiate()
	root.add_child(menu)
	var worlds_button := menu.get_node_or_null("ReferenceInterface/LeftRail/PersistentWorldsButton")
	assert(worlds_button is Button, "Persistent WORLDS entry missing from main menu")
	assert(menu.has_method("_open_server_browser"), "Main menu browser action missing")
	var browser := load("res://scenes/online/server_browser_screen.tscn") as PackedScene
	assert(browser != null, "Persistent server browser scene must load")
	var screen := browser.instantiate()
	assert(screen.get_node_or_null("Center/Panel/Margins/Content/Scroll/ServerList") is VBoxContainer, "Server list layout missing")
	screen.free()
	menu.queue_free()
	print("[online_persistent_world_menu_smoke] PASS")
	quit()
