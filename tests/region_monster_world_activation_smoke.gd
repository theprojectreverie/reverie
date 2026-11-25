extends Node
const WORLD_PATH := "res://scenes/world/greenward_world.tscn"

func _ready() -> void:
	call_deferred("_run")

func _run() -> void:
	print("WORLD ACTIVATION / INACTIVE MONSTER QA: starting")
	var world := (load(WORLD_PATH) as PackedScene).instantiate() as GreenwardWorld
	assert(world != null)
	world.region_id = "elderwood_grove"
	add_child(world)
	await get_tree().process_frame
	await get_tree().physics_frame
	var runtime := world.get_node_or_null("WorldRuntime")
	if runtime != null:
		runtime.set_process(false)
		runtime.set_physics_process(false)
	var player := Node2D.new()
	player.name = "ActivationTestPlayer"
	player.add_to_group("player")
	world.add_child(player)
	await get_tree().process_frame
	var monsters: Array = world.monsters
	assert(monsters.size() == 3)

	var session := GameWorldSessionComponent.new()
	var transition := Node.new()
	transition.set_script(load("res://scripts/game/game_world_transition_component.gd"))
	transition.name = "Transition"
	var activation := GameWorldActivationComponent.new()
	activation.name = "Activation"
	var persistence := Node.new()
	persistence.set_script(load("res://scripts/game/game_world_persistence_component.gd"))
	persistence.name = "Persistence"
	session.add_child(transition)
	session.add_child(activation)
	session.add_child(persistence)
	add_child(session)
	session.world = world
	activation.configure(session)

	for monster in monsters:
		monster.set_process(true)
		monster.set_physics_process(true)
		monster.position = monster.home_position
		monster.set("_roam_target", monster.home_position)
		monster.set("_engagement_cooldown", 0.0)
		monster.engaged = false
		monster.defeated = false

	activation.set_active(false)
	assert(world.process_mode == Node.PROCESS_MODE_DISABLED)
	assert(not bool(world.player.get("input_enabled")))
	var frozen_positions: Dictionary = {}
	for monster in monsters:
		frozen_positions[monster.get_instance_id()] = monster.position
	await get_tree().create_timer(1.0).timeout
	for monster in monsters:
		assert(monster.position.is_equal_approx(frozen_positions[monster.get_instance_id()]), "Monster moved while parent world was inactive")
	print("WORLD DEACTIVATION: PASS (all 3 live monster positions frozen; player input disabled)")

	activation.set_active(true)
	assert(world.process_mode == Node.PROCESS_MODE_INHERIT)
	assert(bool(world.player.get("input_enabled")))
	for monster in monsters:
		assert(monster.is_processing())
	print("WORLD REACTIVATION: PASS (world and player input restored)")

	activation.set_active(false)
	for monster in monsters:
		monster.set_process(false)
		monster.set_physics_process(false)
	session.queue_free()
	world.queue_free()
	await get_tree().process_frame
	print("WORLD ACTIVATION / INACTIVE MONSTER QA: PASS")
	get_tree().quit(0)
