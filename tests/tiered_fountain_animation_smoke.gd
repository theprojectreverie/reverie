extends SceneTree

func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var packed := load("res://scenes/world/castle_gardens/v2/water/fountain_tiered.tscn") as PackedScene
	if packed == null:
		push_error("Tiered fountain scene failed to load")
		quit(1)
		return
	var fountain := packed.instantiate()
	root.add_child(fountain)
	await process_frame
	var player := fountain.get_node("AnimationPlayer") as AnimationPlayer
	var spray := fountain.get_node("Spray") as Sprite2D
	if not player.is_playing() or player.current_animation != &"flow":
		push_error("Tiered fountain authored flow animation did not autoplay")
		quit(1)
		return
	var first_frame := spray.frame
	await create_timer(0.24).timeout
	if spray.frame == first_frame:
		push_error("Tiered fountain spray animation did not advance")
		quit(1)
		return
	print("TIERED FOUNTAIN NODE ANIMATION SMOKE: PASS (removed frame-script dependency, authored AnimationPlayer timeline)")
	quit(0)
