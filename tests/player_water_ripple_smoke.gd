extends Node

func _ready() -> void:
	call_deferred("_run")

func _run() -> void:
	var packed := load("res://scenes/characters/player.tscn") as PackedScene
	assert(packed != null, "Player scene must load with its water-surface animation")
	var player := packed.instantiate() as Node2D
	assert(player != null, "Player instance must be created")
	add_child(player)
	await get_tree().process_frame
	var presentation := player.get_node("PresentationComponent")
	var surface := player.get_node("WaterSurface") as Sprite2D
	var ripple := surface.get_node("AnimationPlayer") as AnimationPlayer
	assert(ripple != null and ripple.has_animation(&"ripple"), "Player water surface must have an authored ripple timeline")
	presentation.call("update_water_visual", true)
	assert(surface.visible, "Water surface must appear when the player enters water")
	assert(ripple.current_animation == "ripple" and ripple.is_playing(), "Water entry must start the ripple animation")
	var original_scale := surface.scale
	ripple.advance(0.9)
	assert(not surface.scale.is_equal_approx(original_scale), "Ripple timeline must animate the water surface")
	presentation.call("update_water_visual", false)
	assert(not surface.visible and not ripple.is_playing(), "Leaving water must hide and stop the ripple")
	assert(surface.scale.is_equal_approx(Vector2(46, 5)), "Leaving water must restore the authored surface scale")
	print("PLAYER WATER RIPPLE SMOKE: PASS (entry activation, authored ripple, exit cleanup)")
	player.queue_free()
	await get_tree().process_frame
	get_tree().quit(0)
