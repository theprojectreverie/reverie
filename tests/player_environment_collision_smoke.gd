extends SceneTree

const WORLD_PATH := "res://scenes/world/castle_royal_gardens.tscn"

func _initialize() -> void:
	call_deferred("_run")

func _blocked_from_outside(player: CharacterBody2D, shape: CollisionShape2D) -> bool:
	var rect := shape.shape as RectangleShape2D
	if rect == null:
		return false
	var global_size := rect.size * Vector2(shape.global_transform.x.length(), shape.global_transform.y.length())
	var direction := Vector2.UP if global_size.y <= global_size.x else Vector2.RIGHT
	var half_extent := global_size.y * 0.5 if direction == Vector2.UP else global_size.x * 0.5
	player.global_position = shape.global_position - direction * (half_extent + 40.0)
	return player.test_move(player.global_transform, direction * (half_extent * 2.0 + 80.0))

func _run() -> void:
	var packed := load(WORLD_PATH) as PackedScene
	assert(packed != null, "Royal Gardens world scene must load")
	var world := packed.instantiate()
	root.add_child(world)
	# Scene smoke tests must not write the user's shared persistent save.
	var world_runtime := world.get_node_or_null("WorldRuntime")
	if world_runtime != null:
		world_runtime.set_process(false)
	await process_frame
	await physics_frame
	var player := world.get("player") as CharacterBody2D
	assert(player != null and player.collision_mask == 1, "Player must collide with authored world geometry")

	var collider_paths := [
		"RoyalCastleArchitecture/CastleCollection/CastleKeep/KeepWallSolid/KeepWallShape",
		"RoyalCastleArchitecture/CastleCollection/CastleKeep/CollisionBody/WestWing",
		"RoyalCastleArchitecture/CastleCollection/CastleKeep/CollisionBody/EastWing",
		"GardenFences/FenceCollision/NorthWestFence",
		"GardenFences/FenceCollision/NorthEastFence",
		"GardenFences/FenceCollision/OuterWestFence",
		"GardenFences/FenceCollision/OuterEastFence",
		"GardenFences/FenceCollision/FrontWestOuterFence",
		"GardenFences/FenceCollision/FrontWestInnerFence",
		"GardenFences/FenceCollision/FrontEastInnerFence",
		"GardenFences/FenceCollision/FrontEastOuterFence"
	]
	for path in collider_paths:
		var shape := world.get_node_or_null(path) as CollisionShape2D
		assert(shape != null and not shape.disabled, "Missing or disabled solid-world collider: " + path)
		var body := shape.get_parent() as StaticBody2D
		assert(body != null and (body.collision_layer & 1) == 1, "Collider must block the player's world layer: " + path)
		assert(_blocked_from_outside(player, shape), "Player must be blocked when approaching: " + path)
	print("PLAYER / PALACE / PERIMETER COLLISION: PASS (%d/%d authored blockers stop the player from outside)" % [collider_paths.size(), collider_paths.size()])

	player.global_position = Vector2(640, 1220)
	assert(not player.test_move(player.global_transform, Vector2(0, -100)), "Grand front gate approach must remain open")
	print("GRAND FRONT GATE: PASS (central approach remains traversable)")

	world.queue_free()
	quit(0)
