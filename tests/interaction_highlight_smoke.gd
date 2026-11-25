extends Node

func _ready() -> void:
	call_deferred("_run")

func _run() -> void:
	var player := Node2D.new()
	player.name = "SmokePlayer"
	player.add_to_group("player")
	player.position = Vector2(40, 0)
	add_child(player)
	var packed := load("res://scenes/world/interactive_prop.tscn") as PackedScene
	assert(packed != null, "Interactive prop scene must load")
	var prop := packed.instantiate() as InteractiveProp
	assert(prop != null, "Interactive prop must instantiate")
	add_child(prop)
	prop.setup("rune_stone", Vector2.ZERO, "Test Rune", "Authored highlight smoke")
	await get_tree().process_frame
	var highlight := prop.get_node("InteractionHighlight") as Node2D
	var player_anim := highlight.get_node("AnimationPlayer") as AnimationPlayer
	assert(player_anim != null and player_anim.has_animation(&"pulse"), "Highlight scene must own its pulse animation")
	for _frame in range(24):
		await get_tree().process_frame
	assert(highlight.visible, "Highlight must appear when player approaches")
	assert(player_anim.is_playing() and player_anim.current_animation == "pulse", "Proximity must start the authored pulse timeline")
	var initial_scale := highlight.scale
	player_anim.advance(0.8)
	assert(not highlight.scale.is_equal_approx(initial_scale), "Highlight scale must be animated by its authored timeline")
	player.position = Vector2(1000, 1000)
	for _frame in range(90):
		await get_tree().process_frame
	assert(not highlight.visible, "Highlight must hide after player leaves its radius")
	assert(not player_anim.is_playing(), "Highlight pulse must stop when inactive")
	assert(highlight.scale.is_equal_approx(Vector2.ONE), "Highlight scale must reset cleanly after stopping")
	var collect_player := prop.get_node("AnimationPlayer") as AnimationPlayer
	assert(collect_player != null and collect_player.has_animation(&"collect"), "Runtime InteractiveProp scene must own its editor-authored collect timeline")
	collect_player.play(&"collect")
	collect_player.advance(0.15)
	assert(prop.scale.x < 1.0 and prop.modulate.a < 1.0, "Collect timeline must animate the reusable prop root")
	collect_player.advance(0.16)
	assert(not prop.visible, "Collect timeline completion must hide the claimed prop")
	print("INTERACTION HIGHLIGHT SMOKE: PASS (proximity pulse, authored collectible timeline, visibility gating and cleanup)")
	get_tree().quit(0)
