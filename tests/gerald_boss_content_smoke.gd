extends SceneTree

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	await process_frame
	var content_db: Node = get_root().get_node("ContentDB")
	var group: Dictionary = content_db.get_enemy_group("gerald_boss_encounter")
	assert(not group.is_empty(), "Gerald boss encounter group is missing.")
	var factory_script: Script = load("res://scripts/combat/combat_factory.gd")
	var units: Array = factory_script.enemy_units("gerald_boss_encounter")
	assert(units.size() == 1, "Gerald boss encounter should create one boss unit.")
	var boss: Combatant = units[0]
	assert(boss.def_id == "gerald_boss", "Unexpected boss definition.")
	assert(boss.is_boss, "Gerald should be marked as a boss.")
	assert(boss.phases.size() == 2, "Gerald should have two phases.")
	print("[GeraldBossSmoke] PASS — boss group, unit, skills and two phases are valid.")
	quit(0)
