extends Node
func _ready() -> void:
	var scene = load("res://scenes/world/tutorial_prologue/training_ground_v02.tscn").instantiate()
	add_child(scene)
	await get_tree().process_frame
	scene._on_practice_hit(false)
	scene._on_practice_hit(false)
	scene._on_practice_hit(true)
	await get_tree().create_timer(2.0).timeout
	var combat = scene.get_node("TutorialHUD/SparringRoot").get_child(0)
	if combat.engine == null:
		get_tree().quit(1)
		return
	print("SPAR_UNITS=", combat.engine.combatants.size())
	for unit in combat.engine.combatants:
		print(unit.def_id, " ", unit.is_boss)
	get_tree().quit(0 if combat.engine.combatants.size() == 2 else 1)