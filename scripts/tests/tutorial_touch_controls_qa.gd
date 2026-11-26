extends Node
func _ready() -> void:
	call_deferred("_run")

func _check(condition: bool, message: String) -> bool:
	if not condition:
		push_error("TOUCH QA FAIL: " + message)
		get_tree().quit(1)
		return false
	return true

func _run() -> void:
	TouchInput.using_touch = true
	var bedroom: Node = load("res://scenes/world/tutorial_prologue/kael_diamond_bedroom.tscn").instantiate()
	add_child(bedroom)
	await get_tree().process_frame
	await get_tree().process_frame
	var hud: Node = bedroom.get_node("TutorialTouchControls")
	var stick := hud.get_node("Controls/Joystick") as Control
	var player := bedroom.get_node("Kael") as Player
	if not _check(stick.is_visible_in_tree(), "bedroom joystick not visible"): return
	var bounds := stick.get_global_rect()
	if not _check(get_viewport().get_visible_rect().encloses(bounds), "joystick outside viewport"): return
	var pos := player.global_position
	var tap := InputEventScreenTouch.new()
	tap.index = 1
	tap.pressed = true
	tap.position = stick.size * 0.5 + Vector2(0,55)
	stick._gui_input(tap)
	if not _check(TouchInput.move_vector.y > 0.5, "touch vector not received"): return
	for i in range(12):
		await get_tree().physics_frame
	if not _check(player.global_position.distance_to(pos) > 3.0, "player not moving"): return
	tap.pressed = false
	stick._gui_input(tap)
	if not _check(TouchInput.move_vector == Vector2.ZERO, "touch not released"): return
	player.input_enabled = false
	await get_tree().process_frame
	await get_tree().process_frame
	if not _check(not stick.is_visible_in_tree(), "controls visible when input locked"): return
	bedroom.queue_free()
	await get_tree().process_frame
	var training: Node = load("res://scenes/world/tutorial_prologue/training_ground_v02.tscn").instantiate()
	add_child(training)
	await get_tree().process_frame
	var th: Node = training.get_node("TutorialTouchControls")
	if not _check(not th.get_node("Controls").visible, "controls visible during dialogue"): return
	for i in range(3):
		training.get_node("TutorialHUD/SparDialogue/Content/Continue").pressed.emit()
		await get_tree().process_frame
	await get_tree().process_frame
	if not _check(th.get_node("Controls/Joystick").is_visible_in_tree(), "training joystick missing after dialogue"): return
	training.set("practice_ready",true)
	await get_tree().process_frame
	await get_tree().process_frame
	if not _check(th.get_node("Controls/Actions/Attack").is_visible_in_tree() and th.get_node("Controls/Actions/Skill").is_visible_in_tree() and th.get_node("Controls/Actions/Dodge").is_visible_in_tree(), "combat buttons missing"): return
	th.get_node("Controls/Actions/Dodge").pressed.emit()
	if not _check(training.get_node("Kael/WorldCombatComponent").dodge_time > 0.0, "dodge not connected"): return
	TouchInput.using_touch = false
	await get_tree().process_frame
	await get_tree().process_frame
	if not _check(not th.get_node("Controls").visible, "desktop controls not hidden"): return
	print("PASS bedroom touchscreen movement/release; tutorial dialogue locking; training action controls; dodge; desktop isolation")
	training.queue_free()
	TouchInput.move_vector = Vector2.ZERO
	await get_tree().process_frame
	await AudioDirector.drain_for_shutdown()
	await get_tree().process_frame
	get_tree().quit()
