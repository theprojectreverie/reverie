extends Node

var destroy_count := 0

func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	var packed := load("res://scenes/world/components/interaction/destructible_object.tscn") as PackedScene
	assert(packed != null, "Reusable destructible scene failed to load")
	var prop := packed.instantiate() as DestructibleObject
	prop.object_id = &"presentation_smoke"
	get_tree().root.add_child(prop)
	await get_tree().process_frame
	var player := prop.get_node("AnimationPlayer") as AnimationPlayer
	var visual := prop.get_node("Visual") as Node2D
	var collision := prop.get_node("CollisionBody/CollisionShape2D") as CollisionShape2D
	assert(player.has_animation("destroy"), "Destructible scene has no authored destroy timeline")
	assert(is_equal_approx(player.get_animation("destroy").length, 0.36), "Destroy timeline duration changed")
	prop.destroyed.connect(_on_destroyed)
	prop.apply_damage(3.0)
	assert(destroy_count == 1 and prop.current_health == 0.0, "Destroy signal or health transition failed")
	assert(prop.visible and player.current_animation == &"destroy", "Destruction presentation did not remain visible during its authored timeline")
	await get_tree().process_frame
	assert(collision.disabled, "Destroyed object collision was not disabled")
	assert(visual.modulate.a > 0.0, "Destroy visual disappeared before its animation completed")
	await get_tree().create_timer(0.42).timeout
	assert(not prop.visible, "Destroyed object was not hidden after the authored timeline")
	var game_state := get_tree().root.get_node("GameState")
	game_state.quest_domain.flags["destructible:presentation_smoke_saved"] = true
	var restored := packed.instantiate() as DestructibleObject
	restored.object_id = &"presentation_smoke_saved"
	get_tree().root.add_child(restored)
	await get_tree().process_frame
	assert(not restored.visible, "Persisted destroyed object should restore hidden without replaying effects")
	assert((restored.get_node("CollisionBody/CollisionShape2D") as CollisionShape2D).disabled, "Persisted destroyed collision was not disabled")
	print("DESTRUCTIBLE AUTHORED PRESENTATION SMOKE: PASS (destroy timeline, immediate collision disable, completion hide, saved-state restore)")
	get_tree().quit(0)


func _on_destroyed() -> void:
	destroy_count += 1
