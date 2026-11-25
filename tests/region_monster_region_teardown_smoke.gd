extends Node
const WORLD_PATH := "res://scenes/world/greenward_world.tscn"

func _ready() -> void:
	call_deferred("_run")

func _run() -> void:
	print("REGION MONSTER TEARDOWN / RE-ENTRY: starting")
	var host := Node2D.new()
	host.name = "WorldHostHarness"
	get_tree().root.add_child(host)

	var first := _make_world("elderwood_grove")
	host.add_child(first)
	await get_tree().process_frame
	await get_tree().physics_frame
	var first_monsters: Array = first.monsters.duplicate()
	assert(first_monsters.size() == 3, "Elderwood should create three monsters")
	for monster in first_monsters:
		assert(is_instance_valid(monster) and monster.is_inside_tree())
		assert(monster.get_parent() != null)
	print("ELDERWOOD INITIAL SPAWNS: PASS (3)")

	# Mirror the transition component's ownership cleanup: detach and queue the
	# previous world, then create the destination in the same single-world host.
	host.remove_child(first)
	first.queue_free()
	var second := _make_world("forsaken_ruins")
	host.add_child(second)
	await get_tree().process_frame
	await get_tree().physics_frame
	assert(not is_instance_valid(first), "Previous region world was not freed")
	for monster in first_monsters:
		assert(not is_instance_valid(monster), "Stale monster survived region teardown")
	assert(host.get_child_count() == 1, "WorldHost retained more than one region")
	assert(host.get_child(0) == second, "Destination world is not sole WorldHost child")
	print("OLD REGION / MONSTER CLEANUP: PASS")

	var second_monsters: Array = second.monsters
	assert(second_monsters.size() == 2, "Forsaken Ruins should create its authored two monsters")
	for monster in second_monsters:
		assert(is_instance_valid(monster) and monster.is_inside_tree())
		assert(monster.get_parent() != null)
		assert(not first_monsters.has(monster), "Destination reused a stale monster instance")
	print("FORSKEN RUINS RE-ENTRY: PASS (2 fresh monsters)")

	var all_group_monsters := get_tree().get_nodes_in_group("world_minimap_monsters")
	assert(all_group_monsters.size() == 2, "Old region monsters remain registered in minimap group")
	for monster in all_group_monsters:
		assert(second_monsters.has(monster), "Stale monster remains in world monster group")
	print("MONSTER GROUP REGISTRY: PASS (destination-only membership)")

	host.queue_free()
	await get_tree().process_frame
	assert(get_tree().get_nodes_in_group("world_minimap_monsters").is_empty(), "Monster group retained entries after final world teardown")
	print("FINAL WORLD TEARDOWN: PASS")
	get_tree().quit(0)

func _make_world(region_id: String) -> GreenwardWorld:
	var packed := load(WORLD_PATH) as PackedScene
	assert(packed != null)
	var world := packed.instantiate() as GreenwardWorld
	assert(world != null)
	world.region_id = region_id
	return world
