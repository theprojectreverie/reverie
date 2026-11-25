extends SceneTree

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var packed := load("res://scenes/ui/title_screen.tscn") as PackedScene
	assert(packed != null, "Title screen scene must load")
	var instance := packed.instantiate() as Control
	root.add_child(instance)
	await process_frame
	var online_button := instance.get_node_or_null("OnlineButton") as Button
	assert(online_button != null, "Online button missing")
	online_button.pressed.emit()
	await process_frame
	assert(instance.has_node("AccountOverlay"), "Online button must open account overlay")
	assert(instance.get_node("AccountOverlay").has_node("Center/Panel/Margins/Content/Tabs"), "Account overlay tabs missing")
	instance.get_node("AccountOverlay").account_authenticated.emit({"name":"TestWanderer"})
	await process_frame
	assert(instance.has_node("CoopLobbyOverlay"), "Successful sign-in must open the co-op lobby")
	assert(instance.get_node("CoopLobbyOverlay").has_node("Center/Panel/Margins/Content/CreateButton"), "Co-op lobby create action missing")
	instance.queue_free()
	await process_frame
	print("[online_title_screen_smoke] PASS")
	quit()
