extends Node

const WORLD_PATH := "res://scenes/world/castle_royal_gardens.tscn"

func _ready() -> void:
	call_deferred("_run")

func _run() -> void:
	print("ROYAL GARDENS MONSTER SPAWN AUDIT: starting")
	var packed := load(WORLD_PATH) as PackedScene
	assert(packed != null, "Royal Gardens scene must load")
	var world := packed.instantiate() as CastleRoyalGardens
	assert(world != null, "Royal Gardens scene must instantiate")
	get_tree().root.add_child(world)
	var runtime := world.get_node_or_null("WorldRuntime")
	if runtime != null:
		runtime.set_process(false)
	await get_tree().process_frame
	await get_tree().physics_frame
	var monsters: Array = world.get_world_monsters()
	var entities := world.get_node("Entities")
	print("SPAWN DIAGNOSTIC: region=%s spawn_records=%d monster_array=%d entity_children=%d" % [world.region_id, (world.region.get("spawns", []) as Array).size(), monsters.size(), entities.get_child_count()])
	var blocked: Array[String] = []
	var checked := 0
	for monster in monsters:
		if monster is RoamingMonster:
			checked += 1
			var local_home: Vector2 = monster.home_position
			if not world.is_walkable(local_home):
				blocked.append("%s@%s" % [monster.group_id, str(local_home)])
	print("ROYAL GARDENS MONSTER SPAWNS: %d checked; blocked=%d" % [checked, blocked.size()])
	for item in blocked:
		push_warning("Monster spawn is inside water or authored blocker: %s" % item)
	world.queue_free()
	await get_tree().process_frame
	get_tree().quit(0)
