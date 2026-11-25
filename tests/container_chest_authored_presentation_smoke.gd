extends Node

func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	var packed := load("res://scenes/world/components/interaction/container_chest.tscn") as PackedScene
	assert(packed != null, "Reusable chest scene failed to load")
	var chest := packed.instantiate()
	get_tree().root.add_child(chest)
	await get_tree().process_frame
	var player := chest.get_node("AnimationPlayer") as AnimationPlayer
	var closed := chest.get_node("Visual/ClosedSprite") as Sprite2D
	var opened := chest.get_node("Visual/OpenSprite") as Sprite2D
	assert(player != null and player.has_animation("open") and player.has_animation("opened"), "Chest animation library is incomplete")
	assert(closed.visible and not opened.visible, "Chest must begin in its closed visual state")
	assert(is_equal_approx(player.get_animation("open").length, 0.24), "Chest opening timeline duration changed")
	chest.interact()
	assert(player.current_animation == &"open", "Chest interaction did not trigger its authored opening timeline")
	player.advance(0.16)
	assert(not closed.visible and opened.visible, "Authored open timeline did not switch chest sprites")
	var collision_shape := chest.get_node("Collision/CollisionShape2D") as CollisionShape2D
	assert(not chest.enabled and not collision_shape.disabled, "Opening the chest changed its interaction/collision contract")
	var restored := packed.instantiate() as ContainerChest
	restored.container_id = &"presentation_smoke"
	var game_state := get_tree().root.get_node("GameState")
	game_state.quest_domain.flags["container:presentation_smoke"] = true
	get_tree().root.add_child(restored)
	await get_tree().process_frame
	var restored_player := restored.get_node("AnimationPlayer") as AnimationPlayer
	var restored_closed := restored.get_node("Visual/ClosedSprite") as Sprite2D
	var restored_open := restored.get_node("Visual/OpenSprite") as Sprite2D
	assert(restored_player.current_animation == &"opened", "Saved chest state did not select the authored opened timeline")
	assert(not restored_closed.visible and restored_open.visible, "Saved chest state did not restore open sprite visibility")
	print("CONTAINER CHEST AUTHORED PRESENTATION SMOKE: PASS (interaction trigger, collision preservation, persisted open-state restoration)")
	get_tree().quit(0)
