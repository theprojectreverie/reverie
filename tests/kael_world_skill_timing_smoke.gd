extends SceneTree

class Target extends Node2D:
	var defeated := false
	var hits := 0
	func receive_world_hit(_amount: float) -> void:
		hits += 1

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	assert(OS.get_environment("REVERIE_E2E_DISABLE_LOCAL_SAVE") == "1")
	var zone = load("res://scenes/world/six_zone_reverie/individual_zones/zone_01_royal_gardens_standalone.tscn").instantiate()
	root.add_child(zone)
	current_scene = zone
	for i in range(5): await physics_frame
	var player = zone.checkpoint_player
	player.set_avatar("kael")
	var combat = player.get_node("WorldCombatComponent")
	var target := Target.new()
	zone.add_child(target)
	target.global_position = player.global_position + Vector2(0, 25)
	target.add_to_group("world_action_targets")
	assert(combat.try_skill())
	assert(combat.skill_pending and target.hits == 0)
	assert(not combat.try_attack() and not combat.try_dodge())
	await create_timer(0.75).timeout
	assert(target.hits == 1 and not combat.skill_pending)
	combat.skill_cooldown = 0
	assert(combat.try_skill())
	combat.receive_world_damage(1.0)
	await create_timer(0.75).timeout
	assert(target.hits == 1 and not combat.skill_pending)
	print("KAEL R SKILL CAST TIMING AND INTERRUPT PASS")
	zone.queue_free()
	await process_frame
	root.get_node("AudioDirector").stop_all_audio_immediately()
	quit()