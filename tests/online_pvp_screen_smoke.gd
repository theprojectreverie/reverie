extends SceneTree

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var screen_scene := load("res://scenes/online/pvp_screen.tscn") as PackedScene
	assert(screen_scene != null, "PvP screen scene must load")
	var screen := screen_scene.instantiate()
	root.add_child(screen)
	await process_frame
	var gateway := root.get_node_or_null("PvpGateway")
	assert(gateway != null and gateway.get_node_or_null("MatchSurrenderRequest") != null, "Surrender HTTP request node must exist")
	for node_path in [
		"Center/Panel/Margins/Content/ActionRow/Actor",
		"Center/Panel/Margins/Content/ActionRow/Skill",
		"Center/Panel/Margins/Content/ActionRow/Target",
		"Center/Panel/Margins/Content/ActionRow/SubmitButton",
		"Center/Panel/Margins/Content/Buttons/QueueButton",
		"Center/Panel/Margins/Content/Buttons/CancelButton",
		"Center/Panel/Margins/Content/Buttons/SurrenderButton"
	]:
		assert(screen.get_node_or_null(node_path) != null, "Missing PvP control: " + node_path)
	assert(screen.get_node("Center/Panel/Margins/Content/Buttons/SurrenderButton").disabled, "Surrender must start disabled")
	screen.queue_free()
	await process_frame
	print("[online_pvp_screen_smoke] PASS")
	quit()
