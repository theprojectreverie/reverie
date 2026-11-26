extends Node2D
func _ready() -> void:
	var user_path := OS.get_user_data_dir()
	if not "reverie_respawn_qa" in user_path.to_lower():
		push_error("QA save isolation not confirmed: " + user_path)
		get_tree().quit(1)
		return
	print("ISOLATED SAVE VERIFIED")
	var zone = load("res://scenes/world/six_zone_reverie/individual_zones/zone_01_royal_gardens_standalone.tscn").instantiate()
	add_child(zone)
	await get_tree().process_frame
	var player = zone.checkpoint_player
	var combat = player.get_node("WorldCombatComponent")
	var mob = zone.get_node("RoseSlime1")
	var starting_gold := GameState.inventory_domain.currency("gold")
	var starting_sap := GameState.inventory_domain.item_count("glade_sap")
	var reward_gold := int(GameState.reward_domain.build_battle_rewards(mob.group_id).gold)
	player.global_position = mob.global_position + Vector2(0, 30)
	player.facing_direction = Vector2.UP
	mob.move_speed = 0.0
	assert(combat.try_attack())
	await get_tree().create_timer(0.8).timeout
	assert(mob.world_hp == 75.0)
	print("KAEL ANIMATED BASIC HIT PASS")
	combat.skill_cooldown = 0.0
	assert(combat.try_skill())
	assert(mob.world_hp == 35.0)
	combat.skill_cooldown = 0.0
	assert(combat.try_skill())
	assert(mob.defeated)
	assert(GameState.inventory_domain.currency("gold") == starting_gold + reward_gold)
	mob.receive_world_hit(1000.0)
	assert(GameState.inventory_domain.currency("gold") == starting_gold + reward_gold)
	assert(GameState.inventory_domain.item_count("glade_sap") == starting_sap + 1)
	print("PLAYER SKILL DEFEAT AND SINGLE REWARD PASS")
	player.global_position += Vector2(0, 120)
	await get_tree().create_timer(1.0).timeout
	assert(not mob.visible)
	await get_tree().create_timer(14.5).timeout
	assert(not mob.defeated and mob.visible and mob.world_hp == mob.max_world_hp and mob.position == mob.home)
	print("FULL MAP REAL-TIME RESPAWN PASS")
	player.global_position = mob.global_position + Vector2(0, 30)
	player.facing_direction = Vector2.UP
	for i in range(3):
		combat.skill_cooldown = 0.0
		assert(combat.try_skill())
	assert(mob.defeated)
	assert(GameState.inventory_domain.currency("gold") == starting_gold + reward_gold * 2)
	mob.receive_world_hit(1000.0)
	assert(GameState.inventory_domain.currency("gold") == starting_gold + reward_gold * 2)
	assert(GameState.inventory_domain.item_count("glade_sap") == starting_sap + 2)
	print("SECOND KILL AND EXACT GOLD REWARDS PASS")
	print("EXACT MATERIAL REWARDS ON BOTH KILLS PASS")
	zone.queue_free()
	for i in range(3):
		await get_tree().process_frame
	AudioDirector.stop_all_audio_immediately()
	await get_tree().create_timer(0.35).timeout
	get_tree().quit()
