extends SceneTree

func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var packed := load("res://scenes/world/castle_royal_gardens.tscn") as PackedScene
	if packed == null:
		push_error("Playable Royal Gardens scene failed to load")
		quit(1)
		return
	var garden := packed.instantiate()
	root.add_child(garden)
	await process_frame
	var water := garden.get_node_or_null("Water")
	if water == null:
		push_error("Playable garden has no Water assembly")
		quit(1)
		return
	for node_name in ["WestFountainWaterFX", "EastFountainWaterFX", "GrandFountainWaterFX"]:
		if water.get_node_or_null("FountainCourt/" + node_name) == null:
			push_error("Playable garden is missing " + node_name)
			quit(1)
			return
	print("PLAYABLE ROYAL GARDENS FOUNTAIN INTEGRATION: PASS (live world scene loads all three animated fountain effects)")
	quit(0)
