extends Node
func _ready() -> void:
	var qa_profile := OS.get_environment("REVERIE_TUTORIAL_QA") == "1"
	if not qa_profile and not "reverie_tutorial_qa" in OS.get_user_data_dir().to_lower():
		get_tree().quit(1)
		return
	await get_tree().process_frame
	var tree := get_tree()
	var scene = load("res://scenes/world/tutorial_prologue/training_ground_v02.tscn").instantiate()
	tree.root.add_child(scene)
	tree.current_scene = scene
	await tree.process_frame
	assert(not scene.player.has_node("FairyCompanion"))
	for i in range(3):
		scene._accept_challenge()
		await tree.process_frame
	scene._open_challenge()
	for i in range(4):
		scene._accept_challenge()
		await tree.process_frame
	scene._on_practice_hit(false)
	scene._on_practice_hit(false)
	scene._on_practice_hit(true)
	scene._open_challenge()
	for i in range(3):
		scene._accept_challenge()
		await tree.process_frame
	await tree.create_timer(2.0).timeout
	var combat = scene.get_node("TutorialHUD/SparringRoot").get_child(0)
	assert(combat.engine.combatants.size() == 2)
	var gold: int = GameState.inventory_domain.currency("gold")
	var deadline := Time.get_ticks_msec() + 45000
	var player_actions := 0
	var enemy_actions := 0
	var enemy = combat.engine.combatants[1]
	var fairy = combat._actor_for_uid(enemy.uid)
	assert(fairy.fairy_art != null and fairy.fairy_art.visible)
	while not combat._resolved and Time.get_ticks_msec() < deadline:
		if not combat._animating and not combat.engine.finished:
			var actor = combat.engine.current_actor()
			if actor != null and actor.team == CombatEngine.PLAYER_TEAM:
				var decision := CombatAI.choose(combat.engine, combat.engine.current_actor_index)
				assert(not str(decision.skill_id).is_empty())
				await combat._session_component.execute_action(str(decision.skill_id), decision.targets)
				player_actions += 1
		await tree.process_frame
	assert(combat._resolved and combat.engine.finished and combat.engine.winner_team == CombatEngine.PLAYER_TEAM)
	for line in combat.engine.log:
		if str(line).contains("Crystal"):
			enemy_actions += 1
	assert(player_actions >= 2 and enemy_actions >= 1)
	assert(fairy.dead)
	assert(fairy.fairy_art.visible)
	assert(fairy.fairy_art.animation == &"surrender" and fairy.fairy_art.frame == 7 and not fairy.fairy_art.is_playing())
	print("ACTUAL DUEL VICTORY: ", player_actions, " player actions, ", enemy_actions, " crystal actions")
	combat._claim(true)
	await tree.process_frame
	assert(scene.farewell_pending)
	assert(scene.get_node("TutorialHUD/SparringRoot").get_child_count() == 0)
	assert(GameState.inventory_domain.currency("gold") == gold)
	assert(not GameState.quest_domain.flags.get("tutorial_complete", false))
	assert(not scene.player.has_node("FairyCompanion"))
	for i in range(5): scene._accept_challenge()
	await tree.create_timer(5.0).timeout
	assert(scene.dialogue_stage == "travel" and scene.player.has_node("FairyCompanion"))
	for i in range(2): scene._accept_challenge()
	await tree.scene_changed
	await tree.process_frame
	var village = tree.current_scene
	assert(village.name == "StandaloneVillage")
	assert(village.checkpoint_player.has_node("FairyCompanion"))
	assert(GameState.quest_domain.flags.get("tutorial_complete", false))
	assert(GameState.session_domain.player_region == "greenward")
	assert(village.checkpoint_player.position.distance_to(Vector2(-2090,112)) < 5.0)
	print("COMBAT CLAIM, VILLAGE TRANSITION, CHECKPOINT AND FAIRY PASS")
	tree.quit()
