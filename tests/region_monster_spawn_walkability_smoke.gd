extends Node
const WORLD_PATH := "res://scenes/world/greenward_world.tscn"
const REGION_ID := "elderwood_grove"

func _ready() -> void:
	call_deferred("_run")

func _run() -> void:
	print("REGION MONSTER SPAWN AUDIT: starting | %s" % REGION_ID)
	var packed := load(WORLD_PATH) as PackedScene
	assert(packed != null, "Greenward world scene must load")
	var world := packed.instantiate() as GreenwardWorld
	assert(world != null, "Greenward world must instantiate")
	world.region_id = REGION_ID
	get_tree().root.add_child(world)
	var runtime := world.get_node_or_null("WorldRuntime")
	if runtime != null:
		runtime.set_process(false)
	await get_tree().process_frame
	await get_tree().physics_frame
	var monsters: Array = world.monsters
	var blocked: Array[String] = []
	var checked := 0
	for monster in monsters:
		if monster is RoamingMonster:
			checked += 1
			var home: Vector2 = monster.home_position
			if not world.is_walkable(home):
				blocked.append("%s@%s" % [monster.group_id, str(home)])
	print("REGION MONSTER SPAWNS: %d checked; blocked=%d" % [checked, blocked.size()])
	for item in blocked:
		push_warning("Monster home position is water or blocked: %s" % item)
	assert(checked > 0, "Selected region must spawn at least one authored monster")
	assert(blocked.is_empty(), "All authored monster spawn homes must be walkable: %s" % str(blocked))
	print("REGION MONSTER SPAWN AUDIT: PASS")
	world.queue_free()
	await get_tree().process_frame
	get_tree().quit(0)
