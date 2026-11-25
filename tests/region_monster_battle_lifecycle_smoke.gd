extends Node
const WORLD_PATH := "res://scenes/world/greenward_world.tscn"
const REGION_ID := "elderwood_grove"

func _ready() -> void:
	call_deferred("_run")

func _run() -> void:
	print("REGION MONSTER BATTLE LIFECYCLE: starting")
	var packed := load(WORLD_PATH) as PackedScene
	assert(packed != null)
	var world := packed.instantiate() as GreenwardWorld
	assert(world != null)
	world.region_id = REGION_ID
	get_tree().root.add_child(world)
	var runtime := world.get_node_or_null("WorldRuntime")
	if runtime != null:
		runtime.set_process(false)
		runtime.set_physics_process(false)
	await get_tree().process_frame
	await get_tree().physics_frame
	var monsters: Array = world.monsters
	assert(monsters.size() == 3, "Expected three Elderwood monsters")
	var player := Node2D.new()
	player.name = "BattleLifecycleDummyPlayer"
	player.add_to_group("player")
	world.add_child(player)
	await get_tree().process_frame

	# Defeat/flee path: engagement freezes passive roaming, then retreat returns
	# the monster home and applies the authored eight-second cooldown.
	var fleeing: RoamingMonster = monsters[0]
	fleeing.set_process(false)
	var flee_home: Vector2 = fleeing.home_position
	fleeing.position = flee_home + Vector2(12.0, 0.0)
	fleeing._roam_target = fleeing.position + Vector2(40.0, 0.0)
	fleeing._begin_encounter()
	assert(fleeing.engaged, "Encounter did not mark monster engaged")
	var engaged_position: Vector2 = fleeing.position
	fleeing._process(0.25)
	assert(fleeing.position.is_equal_approx(engaged_position), "Engaged monster moved during battle")
	fleeing._on_battle_finished({"group_id": fleeing.group_id, "victory": false})
	assert(not fleeing.engaged, "Flee result left monster engaged")
	assert(fleeing.position.is_equal_approx(flee_home), "Flee result did not return monster home")
	assert(fleeing.get("_roam_target").is_equal_approx(flee_home), "Flee result retained stale roam target")
	assert(float(fleeing.get("_engagement_cooldown")) >= 7.99, "Flee result missed eight-second cooldown")
	var cooldown_position: Vector2 = fleeing.position
	fleeing._process(0.25)
	assert(fleeing.position.is_equal_approx(cooldown_position), "Monster moved during engagement cooldown")
	assert(not fleeing.can_interact(), "Monster remained interactable during cooldown")
	print("BATTLE RETREAT / COOLDOWN: PASS")

	# Victory path: use a short test-only respawn duration and exercise the
	# production async defeat/respawn routine without waiting 75 seconds.
	var victorious: RoamingMonster = monsters[1]
	victorious.set_process(false)
	var victory_home: Vector2 = victorious.home_position
	victorious.position = victory_home + Vector2(18.0, 0.0)
	victorious.set("respawn_seconds", 0.05)
	victorious._roam_target = victorious.position + Vector2(50.0, 0.0)
	victorious._begin_encounter()
	victorious._on_battle_finished({"group_id": victorious.group_id, "victory": true})
	assert(victorious.defeated, "Victory did not mark monster defeated")
	assert(not victorious.engaged, "Victory left monster engaged")
	assert(not victorious.enabled and not victorious.visible, "Defeated monster remained interactive/visible")
	assert(not victorious.can_interact(), "Defeated monster remained interactable")
	await get_tree().create_timer(0.12).timeout
	assert(not victorious.defeated, "Monster did not respawn after timer")
	assert(victorious.enabled and victorious.visible, "Respawn did not restore visibility/interactions")
	assert(victorious.position.is_equal_approx(victory_home), "Respawn did not restore home position")
	assert(victorious.get("_roam_target").is_equal_approx(victory_home), "Respawn retained stale roam target")
	assert(float(victorious.get("_engagement_cooldown")) == 0.0, "Respawn retained engagement cooldown")
	assert(not bool(victorious.health_component.get("is_dead")), "Respawn health remained dead")
	assert(victorious.can_interact(), "Respawned monster is not interactable")
	print("VICTORY / DEFEAT / RESPAWN: PASS")

	# A battle-finished event for another group must not alter a third monster.
	var untouched: RoamingMonster = monsters[2]
	untouched.set_process(false)
	var untouched_position: Vector2 = untouched.position
	var untouched_target: Vector2 = untouched.get("_roam_target")
	untouched._begin_encounter()
	untouched._on_battle_finished({"group_id": "unrelated_group", "victory": true})
	assert(untouched.engaged, "Unrelated battle result changed engagement")
	assert(untouched.position.is_equal_approx(untouched_position), "Unrelated result moved monster")
	assert(untouched.get("_roam_target").is_equal_approx(untouched_target), "Unrelated result changed target")
	print("UNRELATED BATTLE EVENT ISOLATION: PASS")

	for monster in monsters:
		monster.set_process(false)
	world.queue_free()
	await get_tree().process_frame
	get_tree().quit(0)
