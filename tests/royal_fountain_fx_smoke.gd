extends SceneTree

func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var packed := load("res://scenes/world/castle_gardens/components/castle_water_assembly.tscn") as PackedScene
	if packed == null:
		push_error("Castle water assembly failed to load")
		quit(1)
		return
	var water := packed.instantiate()
	root.add_child(water)
	await process_frame
	var court := water.get_node("FountainCourt")
	var names := ["WestFountainWaterFX", "EastFountainWaterFX", "GrandFountainWaterFX"]
	for node_name in names:
		var fx := court.get_node_or_null(node_name)
		if fx == null:
			push_error("Missing live fountain FX instance: " + node_name)
			quit(1)
			return
		var player := fx.get_node("AnimationPlayer") as AnimationPlayer
		var spray := fx.get_node("Spray") as Sprite2D
		var ripple := fx.get_node("BasinRipple") as Line2D
		if not player.is_playing() or player.current_animation != &"flow":
			push_error("Fountain flow timeline is not playing: " + node_name)
			quit(1)
			return
		if spray.hframes != 6 or ripple.points.size() < 8:
			push_error("Fountain authored effect nodes are incomplete: " + node_name)
			quit(1)
			return
	var west_spray := court.get_node("WestFountainWaterFX/Spray") as Sprite2D
	var first_frame := west_spray.frame
	await create_timer(0.24).timeout
	if west_spray.frame == first_frame:
		push_error("Fountain spray frame timeline did not advance")
		quit(1)
		return
	print("ROYAL FOUNTAIN FX SMOKE: PASS (three live fountain instances, authored sprite-sheet timeline and basin ripples)")
	quit(0)
