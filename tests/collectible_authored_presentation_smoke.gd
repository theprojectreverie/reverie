extends Node

func _ready() -> void:
	var packed := load("res://scenes/world/components/interaction/collectible_object.tscn") as PackedScene
	assert(packed != null, "collectible scene failed to load")
	var collectible := packed.instantiate() as CollectibleObject
	assert(collectible != null, "collectible root type mismatch")
	add_child(collectible)
	var player := collectible.get_node("AnimationPlayer") as AnimationPlayer
	assert(player != null and player.has_animation("collect"), "authored collect animation missing")
	var animation := player.get_animation("collect")
	assert(is_equal_approx(animation.length, 0.3), "collect animation duration changed")
	assert(animation.get_track_count() == 2, "collect animation should only animate scale and opacity")
	assert(String(animation.track_get_path(0)) == "Sprite2D:scale", "scale track path changed")
	assert(String(animation.track_get_path(1)) == "Sprite2D:modulate", "opacity track path changed")
	assert(collectible.get_node("Sprite2D") != null, "existing Sprite2D path must remain stable")
	assert(collectible.enabled, "fresh collectible should remain enabled")
	print("COLLECTIBLE AUTHORED PRESENTATION SMOKE: PASS (scene load, reusable timeline, stable Sprite2D path, fresh interaction state)")
	get_tree().quit()
