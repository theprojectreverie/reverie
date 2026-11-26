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

	for attempt in 120:
		await get_tree().process_frame
		if battle.engine != null:
			break
	assert(battle.engine != null, "Gerald combat must initialize without backstory.")
	var boss_count := 0
	for unit in battle.engine.combatants:
		if unit.is_boss:
			boss_count += 1
	assert(boss_count == 1, "Gerald encounter should stage exactly one boss.")
	await get_tree().process_frame
	assert(battle.get_node_or_null("GeraldBossIntro") == null, "No memory cinematic should exist inside the combat scene.")
	print("[GeraldBossIntegrationSmoke] PASS: battle initializes without story overlay.")
	battle.queue_free()
	await get_tree().process_frame
	await AudioDirector.drain_for_shutdown()
	get_tree().quit()
