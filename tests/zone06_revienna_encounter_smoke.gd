extends Node2D
var ok := true

func check(value: bool, label: String) -> void:
	print("REVIENNA_TEST ", label, "=", value)
	ok = ok and value

func _ready() -> void:
	# Avoid writing checkpoints during this test.
	var tutorial_before: Variant = GameState.quest_domain.flags.get("tutorial_complete", false)
	GameState.quest_domain.flags["tutorial_complete"] = false
	var zone := preload("res://scenes/world/six_zone_reverie/individual_zones/zone_06_ruined_tower_standalone.tscn").instantiate()
	add_child(zone)
	await get_tree().process_frame
	var actor := zone.get_node("ReviennaEncounter")
	var throne := zone.get_node("Zone/Revienna/AnimatedSprite2D") as AnimatedSprite2D
	check(throne.sprite_frames.get_frame_count(&"idle") == 7 and throne.sprite_frames.get_animation_loop(&"idle") and throne.is_playing(), "throne_idle")
	check(throne.get_parent().global_position == actor.global_position, "throne_encounter_alignment")
	var player := zone.get("checkpoint_player") as CharacterBody2D
	var dialog := zone.get_node("UI/Dialogue") as DialogueBox
	var router := zone.get_node("CombatRouter") as GameCombatRouterComponent
	var units := CombatFactory.enemy_units("revienna_encounter")
	check(units.size() == 1 and units[0].is_boss and units[0].def_id == "revienna_boss", "boss_definition")
	player.global_position = Vector2(0, 1170)
	player.get_node("InteractionComponent").refresh_nearest()
	check(player.get_node("InteractionComponent").get_current() == actor, "approach")
	player.try_interact()
	check(dialog.visible and not player.input_enabled, "dialogue_open")
	dialog.close()
	await get_tree().process_frame
	check(router.active_combat == null and player.input_enabled, "cancel_no_battle")
	player.try_interact()
	dialog._show_node("warning")
	dialog._choose({"text":"Not yet", "next":""})
	await get_tree().process_frame
	check(router.active_combat == null and player.input_enabled, "decline_no_battle")
	player.try_interact()
	dialog._show_node("warning")
	dialog._choose({"text":"Challenge Revienna", "next":""})
	for i in range(12):
		await get_tree().process_frame
	check(router.active_combat != null and not player.input_enabled, "battle_launch")
	if router.active_combat != null:
		var battle := router.active_combat
		check(battle.group_id == "revienna_encounter" and battle.engine != null, "combat_engine")
		var art := battle.find_child("ReviennaArt", true, false)
		var visible_art := false
		for node in battle.find_children("ReviennaArt", "Node2D", true, false):
			if node.visible:
				visible_art = true
		check(visible_art, "authored_boss_art")
		battle._claim(false)
		await get_tree().process_frame
		check(router.active_combat == null and player.input_enabled and actor.can_interact(), "retry_after_retreat")
	# Simulate the result signal, not an actual reward claim; restore the save flag immediately.
	player.get_node("InteractionComponent").refresh_nearest()
	player.try_interact()
	dialog._show_node("warning")
	dialog._choose({"text":"Challenge Revienna", "next":""})
	for i in range(12):
		await get_tree().process_frame
	check(router.active_combat != null, "second_battle")
	if router.active_combat != null:
		var had_flag: bool = GameState.quest_domain.flags.has("revienna_defeated")
		var previous: Variant = GameState.quest_domain.flags.get("revienna_defeated", false)
		EventBus.battle_finished.emit({"group_id":"revienna_encounter", "victory":true, "rewards":{}})
		check(bool(GameState.quest_domain.flags.get("revienna_defeated", false)) and not actor.can_interact(), "victory_flag_and_lock")
		if had_flag:
			GameState.quest_domain.flags["revienna_defeated"] = previous
		else:
			GameState.quest_domain.flags.erase("revienna_defeated")
		router.active_combat._claim(false)
		for i in range(4):
			await get_tree().process_frame
		check(dialog.visible and dialog._dialogue_id == "revienna_victory" and not player.input_enabled, "victory_dialogue")
		dialog.close()
		check(player.input_enabled, "victory_return_to_world")
	GameState.quest_domain.flags["tutorial_complete"] = tutorial_before
	print("REVIENNA_TEST_PASS=", ok)
	zone.queue_free()
	for _frame in range(3):
		await get_tree().process_frame
	AudioDirector.stop_all_audio_immediately()
	await get_tree().create_timer(0.35).timeout
	get_tree().quit(0 if ok else 1)
