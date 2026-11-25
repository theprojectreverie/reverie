extends Node

func _ready() -> void:
	call_deferred("_run")

func _run() -> void:
	var packed := load("res://scenes/ui/combat_screen.tscn") as PackedScene
	assert(packed != null, "Combat screen scene failed to load.")
	var battle := packed.instantiate() as CombatScreen
	assert(battle != null, "Combat screen failed to instantiate.")
	battle.group_id = "gerald_boss_encounter"
	get_tree().root.add_child(battle)

	var intro: Control = null
	for attempt in 60:
		await get_tree().process_frame
		intro = battle.get_node_or_null("GeraldBossIntro") as Control
		if intro != null:
			break
	assert(intro != null, "Gerald cinematic did not appear before combat.")

	var skip_button := intro.get_node("SkipButton") as Button
	skip_button.pressed.emit()

	for attempt in 120:
		await get_tree().process_frame
		if battle.engine != null:
			break
	assert(battle.engine != null, "Combat did not initialize after cinematic skip.")
	var boss_count := 0
	for unit in battle.engine.combatants:
		if unit.is_boss:
			boss_count += 1
	assert(boss_count == 1, "Gerald encounter should stage exactly one boss.")
	await get_tree().process_frame
	assert(battle.get_node_or_null("GeraldBossIntro") == null, "Cinematic overlay should be released after Skip.")
	print("[GeraldBossIntegrationSmoke] PASS — intro appears, Skip advances, overlay cleans up, and Gerald battle initializes.")
	battle.queue_free()
	get_tree().quit()
