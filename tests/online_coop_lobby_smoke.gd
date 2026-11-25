extends SceneTree

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var packed := load("res://scenes/online/coop_lobby_screen.tscn") as PackedScene
	assert(packed != null, "Co-op lobby scene must load")
	var instance := packed.instantiate()
	root.add_child(instance)
	await process_frame
	for node_path in [
		"Center/Panel/Margins/Content/CreateButton",
		"Center/Panel/Margins/Content/JoinButton",
		"Center/Panel/Margins/Content/Actions/RefreshButton",
		"Center/Panel/Margins/Content/Actions/LeaveButton"
	]:
		assert(instance.get_node_or_null(node_path) != null, "Missing co-op lobby control: " + node_path)
	instance.queue_free()
	await process_frame
	print("[online_coop_lobby_smoke] PASS")
	quit()
