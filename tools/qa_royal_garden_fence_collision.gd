extends SceneTree

const WORLD_PATH := "res://scenes/world/castle_royal_gardens.tscn"

func _initialize() -> void:
	call_deferred("_run")

func _ray_hits_fence(fences: Node2D, start_local: Vector2, end_local: Vector2) -> bool:
	var query := PhysicsRayQueryParameters2D.create(fences.to_global(start_local), fences.to_global(end_local), 1)
	var result := fences.get_world_2d().direct_space_state.intersect_ray(query)
	return not result.is_empty() and result.get("collider") == fences.get_node("FenceCollision")

func _ray_is_clear(fences: Node2D, start_local: Vector2, end_local: Vector2) -> bool:
	var query := PhysicsRayQueryParameters2D.create(fences.to_global(start_local), fences.to_global(end_local), 1)
	return fences.get_world_2d().direct_space_state.intersect_ray(query).is_empty()

func _run() -> void:
	var packed := load(WORLD_PATH) as PackedScene
	assert(packed != null, "Royal Gardens scene must load")
	var world := packed.instantiate() as Node2D
	root.add_child(world)
	await physics_frame
	await physics_frame
	var fences := world.get_node_or_null("GardenFences") as Node2D
	assert(fences != null, "GardenFences root is required")
	var body := fences.get_node_or_null("FenceCollision") as StaticBody2D
	assert(body != null, "Visible garden fences must have a static collision body")
	assert(body.collision_layer == 1, "Fence collision must be on the player's world collision layer")
	assert(body.get_child_count() == 8, "Expected eight authored fence collision segments")
	var barriers := [
		["north west", Vector2(129.7, 25), Vector2(129.7, 135)],
		["north east", Vector2(1150.9, 25), Vector2(1150.9, 135)],
		["outer west", Vector2(-155, 620), Vector2(-25, 620)],
		["outer east", Vector2(1305, 620), Vector2(1435, 620)],
		["front west outer", Vector2(224, 1110), Vector2(224, 1210)],
		["front west inner", Vector2(476, 1110), Vector2(476, 1210)],
		["front east inner", Vector2(804, 1110), Vector2(804, 1210)],
		["front east outer", Vector2(1056, 1110), Vector2(1056, 1210)],
	]
	for barrier in barriers:
		assert(_ray_hits_fence(fences, barrier[1], barrier[2]), "Fence collision missing at %s rail" % barrier[0])
		print("FENCE COLLISION: PASS (%s)" % barrier[0])
	for gate_x in [335.0, 640.0, 945.0]:
		assert(_ray_is_clear(fences, Vector2(gate_x, 1110), Vector2(gate_x, 1210)), "Authored gate opening at x=%.1f must remain clear" % gate_x)
		print("GATE PASSAGE: PASS (x=%.1f)" % gate_x)
	print("ROYAL GARDEN FENCE COLLISION: PASS (8 barriers, 3 gate openings clear)")
	world.queue_free()
	quit(0)
