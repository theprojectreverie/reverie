extends Node
## Runtime smoke test for the authored combat HUD and image-backed controls.

func _ready() -> void:
	call_deferred("_run")

func _run() -> void:
	var packed := load("res://scenes/ui/combat_screen.tscn") as PackedScene
	if packed == null:
		push_error("Combat screen scene failed to load.")
		get_tree().quit(1)
		return
	var battle := packed.instantiate() as CombatScreen
	battle.group_id = "elder_hollow"
	add_child(battle)
	for _frame in range(120):
		await get_tree().process_frame
	# Skill visibility depends on whose turn it is. Use a fixed player actor so
	# this smoke test validates the HUD rather than random enemy initiative.
	var test_player := Combatant.new()
	test_player.uid = "runtime_smoke_player"
	test_player.display_name = "Runtime Smoke Player"
	test_player.max_hp = 100.0
	test_player.hp = 100.0
	test_player.atk = 30.0
	test_player.defense = 20.0
	test_player.speed = 100.0
	test_player.skills = ["gale_shot"]
	var test_enemy := Combatant.new()
	test_enemy.uid = "runtime_smoke_enemy"
	test_enemy.display_name = "Runtime Smoke Enemy"
	test_enemy.max_hp = 100.0
	test_enemy.hp = 100.0
	test_enemy.atk = 10.0
	test_enemy.defense = 10.0
	test_enemy.speed = 1.0
	var test_engine := CombatEngine.new()
	test_engine.setup([test_player], [test_enemy], 741)
	test_engine.start()
	battle._turn_token += 1
	battle.engine = test_engine
	battle._resolved = false
	battle._animating = false
	battle._hud_component.refresh_skills()
	var ok := true
	if battle._skills_box == null or battle._hint_label == null:
		push_error("Combat HUD did not bind the authored skill controls.")
		ok = false
	if battle._log_label == null or not battle._log_label.bbcode_enabled:
		push_error("Combat log must render BBCode markup.")
		ok = false
	if battle._auto_button == null or battle._auto_button.icon == null:
		push_error("Auto battle icon asset did not load.")
		ok = false
	if battle._speed_button == null or battle._speed_button.icon == null:
		push_error("Battle speed icon asset did not load.")
		ok = false
	if battle._auto_button != null and battle._auto_button.icon != null and battle._auto_button.icon.get_width() != 28:
		push_error("Auto battle icon must use its 28px authored derivative.")
		ok = false
	if battle._speed_button != null and battle._speed_button.icon != null and battle._speed_button.icon.get_width() != 28:
		push_error("Battle speed icon must use its 28px authored derivative.")
		ok = false
	for control_path in ["CombatScreenLayout/Root/CombatHeader/AutoButton", "CombatScreenLayout/Root/CombatHeader/SpeedButton", "CombatScreenLayout/Root/CombatHeader/RetreatButton"]:
		var header_control := battle.get_node_or_null(control_path) as Button
		if header_control == null or not (header_control.get_theme_stylebox("normal") is StyleBoxTexture):
			push_error("Battle header controls must use the authored panel texture: " + control_path)
			ok = false
	battle._cycle_speed()
	if battle._speed_button == null or battle._speed_button.text != "1.6×":
		push_error("Battle speed control must use the compact, readable multiplier label.")
		ok = false
	var log_caption := battle.get_node_or_null("CombatScreenLayout/Root/CombatBottomHUD/LogPanel/LogContent/LogCaption") as Label
	if log_caption == null or log_caption.visible:
		push_error("Battle log must not duplicate the title already present in its authored frame.")
		ok = false
	if battle._log_label != null and battle._log_label.get_theme_font_size("normal_font_size") < 11:
		push_error("Battle log body text must remain readable at the revised 11px baseline.")
		ok = false
	var report := battle.skill_presentation_report()
	if int(report.get("skill_buttons", 0)) <= 0:
		push_error("Combat screen did not populate the live skill buttons.")
		ok = false
	if battle._skills_box != null and battle._skills_box.get_child_count() > 0:
		var skill_card := battle._skills_box.get_child(0) as Button
		if skill_card == null or not (skill_card.get_theme_stylebox("normal") is StyleBoxTexture):
			push_error("Ability cards must use the authored ornamental panel texture.")
			ok = false
	else:
		push_error("Combat screen did not create an inspectable ability card.")
		ok = false
	if battle._log_label != null and battle._log_label.get_parsed_text().is_empty():
		push_error("Combat log did not receive the battle-start events.")
		ok = false
	var field := battle._battlefield as Battlefield
	if field == null or field._stage == null:
		push_error("Battlefield stage must be available for authored hit impacts.")
		ok = false
	else:
		field._generic_attack_component._spawn_attack_trail(field.actors()[0] as BattlefieldActor, Vector2(100, 100), Vector2(220, 160), "fire")
		await get_tree().process_frame
		var projectile_found := false
		for child in field._generic_attack_component.get_children():
			if child.has_node("Art") and child.has_node("AnimationPlayer"):
				var projectile_player := child.get_node("AnimationPlayer") as AnimationPlayer
				if projectile_player != null and projectile_player.has_animation(&"flight"):
					projectile_found = true
		if not projectile_found:
			push_error("Generic attack choreography did not spawn the reusable authored projectile scene.")
			ok = false
		var attack_owner := field.actors()[0] as BattlefieldActor
		if not attack_owner._attack_effects.is_empty():
			push_error("A launched projectile must be released from the attacker while its authored flight completes independently.")
			ok = false
		field.spawn_damage_number(attack_owner, "-17", UITheme.DANGER, 0.8)
		var delayed_number_found := false
		for child in field._stage.get_children():
			if child is Label and child.text == "-17":
				delayed_number_found = true
		if not delayed_number_found:
			push_error("Delayed damage number was not attached to the battlefield stage.")
			ok = false
		# Resolving the encounter must cancel both a travelling projectile and a
		# number whose display timer has not fired yet.
		battle._finish_battle(false)
		for _frame in range(3):
			await get_tree().process_frame
		if not attack_owner._attack_effects.is_empty():
			push_error("Battle resolution left attacker-owned travelling effects alive.")
			ok = false
		for child in field._stage.get_children():
			if child is Label and child.text == "-17":
				push_error("Battle resolution left a delayed floating combat number alive.")
				ok = false
		var field_actors := field.actors()
		if field_actors.size() >= 2:
			field.spawn_hit_effect(field_actors[1], field_actors[0], Color("#ff9b5e"), 1.2)
			field.spawn_hit_effect(field_actors[0], field_actors[1], Color("#ffe07a"), 1.5)
			await get_tree().process_frame
			var normal_found := false
			var critical_found := false
			for child in field._stage.get_children():
				if child.has_node("Art") and child.has_node("AnimationPlayer"):
					var hit_player := child.get_node("AnimationPlayer") as AnimationPlayer
					if hit_player == null or not hit_player.is_playing():
						push_error("Authored hit effect did not start its animation.")
						ok = false
					elif hit_player.current_animation == "impact":
						normal_found = true
					elif hit_player.current_animation == "critical":
						critical_found = true
			if not normal_found or not critical_found:
				push_error("Battlefield must spawn both standard and critical authored impact variants.")
				ok = false
		else:
			push_error("Battlefield smoke fixture needs at least two actors for a hit-impact check.")
			ok = false
	var teardown_effect: Node = null
	if field != null and not field.actors().is_empty():
		var teardown_owner := field.actors()[0] as BattlefieldActor
		field._generic_attack_component._spawn_attack_trail(teardown_owner, Vector2(120, 120), Vector2(260, 180), "fire")
		await get_tree().process_frame
		for child in field._generic_attack_component.get_children():
			if child.has_node("Art") and child.has_node("AnimationPlayer"):
				teardown_effect = child
				break
		if teardown_effect == null:
			push_error("Scene teardown fixture failed to create a travelling projectile.")
			ok = false
	battle.queue_free()
	for _frame in range(3):
		await get_tree().process_frame
	if is_instance_valid(teardown_effect):
		push_error("Combat screen teardown left its travelling projectile alive.")
		ok = false
	if ok:
		print("COMBAT SCREEN RUNTIME SMOKE: PASS")
		print("SKILL_BUTTONS=", report.get("skill_buttons", 0))
		print("BATTLEFIELD=true; RESOLUTION_AND_TEARDOWN_CLEANUP=true")
	get_tree().quit(0 if ok else 1)
