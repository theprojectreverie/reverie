extends Node
func _ready() -> void:
	call_deferred("run")
func fail(reason: String) -> void:
	print("FAIL ",reason)
	get_tree().quit(1)
func wait_until(check: Callable, seconds: float=35.0) -> bool:
	var deadline := Time.get_ticks_msec()+int(seconds*1000)
	while not check.call():
		if Time.get_ticks_msec()>deadline:return false
		await get_tree().process_frame
	return true
func run() -> void:
	if OS.get_environment("QA_TABLET_BATTLE")=="1":
		TouchInput.using_touch=true
	AuthGateway.api_base_url=OS.get_environment("QA_API")
	if AuthGateway.login(OS.get_environment("QA_NAME"),OS.get_environment("QA_PASSWORD"))!=OK:
		fail("login");return
	var auth=await AuthGateway.auth_result
	if not auth[1]:fail("auth");return
	var training = load("res://scenes/world/tutorial_prologue/training_ground_v02.tscn").instantiate()
	get_tree().root.add_child(training)
	get_tree().current_scene=training
	for i in range(3):training._accept_challenge()
	training._open_challenge()
	if not await wait_until(func():return training.dialogue_stage=="practice"):
		fail("training named practice");return
	if training.companion_name!="Astra":
		fail("training name restored");return
	for i in range(4):training._accept_challenge()
	training._on_practice_hit(false)
	training._on_practice_hit(false)
	training._on_practice_hit(true)
	if not training.dummy_complete:
		fail("dummy practice");return
	training._open_challenge()
	for i in range(3):training._accept_challenge()
	var battle := training.get_node("TutorialHUD/SparringRoot").get_child(0) as CombatScreen
	if not await wait_until(func():return is_instance_valid(battle) and battle.engine!=null and not battle._animating):
		fail("authoritative start");return
	if OS.get_environment("QA_TABLET_BATTLE")=="1":
		for frame in range(4):await get_tree().process_frame
		var viewport_bounds:=battle.get_viewport_rect()
		var root_bounds:Rect2=battle.get_global_rect()
		if root_bounds.position.distance_to(viewport_bounds.position)>1.0 or root_bounds.size.distance_to(viewport_bounds.size)>1.0:
			fail("battle not fullscreen "+str(root_bounds)+" viewport "+str(viewport_bounds));return
		if not battle._hud_component._mobile_hud:
			fail("tablet mode missing");return
		for category in battle._hud_component._category_buttons:
			var button:Control=battle._hud_component._category_buttons[category]
			if not button.is_visible_in_tree() or not viewport_bounds.grow(1).encloses(button.get_global_rect()):
				fail("clipped category "+str(category)+" "+str(button.get_global_rect()));return
		for child in battle._skills_box.get_children():
			if child is Control and not viewport_bounds.grow(1).encloses(child.get_global_rect()):
				fail("clipped skill card "+str(child.get_global_rect()));return
		print("PASS full-screen tablet battle, six visible action categories, skill card bounds ",viewport_bounds)
	var session := battle._session_component
	if session._spar_id.is_empty() or not session._spar_actor.begins_with("p_server:"):
		fail("server battle identity");return
	battle._speed=8.0
	var initial := session._spar_sequence
	await session.defend()
	if session._spar_sequence!=initial+1:
		fail("defend sequence");return
	for n in range(20):
		if battle._resolved:break
		var actor := battle.engine.current_actor()
		if actor==null:fail("no player actor");return
		var enemies := battle.engine.living_indices(CombatEngine.ENEMY_TEAM)
		if enemies.is_empty():break
		var before := session._spar_sequence
		await session.execute_action(str(actor.skills[0]),[enemies[0]])
		if session._spar_sequence<=before and not battle._resolved:
			fail("skill sequence");return
	if not await wait_until(func():return battle._resolved):
		fail("battle result");return
	if not session._spar_verified:
		fail("expected verified victory");return
	if not await wait_until(func():return battle._result_layer!=null):
		fail("result overlay");return
	if not session._spar_unlock_notice:
		fail("unlock notice missing");return
	var details: VBoxContainer = battle._result_layer.get_node("Center/Panel/Content/Details")
	var found := false
	for child in details.get_children():
		if child is Label and "ILLUSTRATION UNLOCKED" in child.text:found=true
	if not found:
		fail("unlock label missing");return
	await battle._result_component.claim(true)
	print("PASS Godot live spar: server identity, defend, skill, confirmed victory, unlock notice acknowledged")
	if training.dialogue_stage!="farewell" or not training.spar_won:
		fail("training verified farewell");return
	for i in range(5):training._accept_challenge()
	if not await wait_until(func():return training.dialogue_stage=="travel",20):
		fail("companion transformation");return
	if not training.player.has_node("FairyCompanion"):
		fail("companion follower");return
	for i in range(2):training._accept_challenge()
	if not await wait_until(func():return get_tree().current_scene!=null and get_tree().current_scene.name==&"StandaloneVillage",35):
		fail("village travel");return
	if not bool(GameState.quest_domain.flags.get("tutorial_complete",false)):
		fail("tutorial checkpoint");return
	var village := get_tree().current_scene
	var player = village.get("checkpoint_player")
	if player==null or not player.has_node("FairyCompanion"):
		fail("village companion follower");return
	print("PASS complete training dialogue, practice, server spar, fairy transformation, village arrival")
	var menu = load("res://scenes/ui/main_menu.tscn").instantiate()
	add_child(menu)
	var selector = menu.get_node("MenuCharacterSelector")
	if not await wait_until(func():return selector._loaded and selector._pending.is_empty() and selector._choices.has("elathra")):
		fail("unlocked gallery");return
	selector.pressed.emit()
	var tile: Button=selector.grid.get_node("elathra")
	if tile.disabled or not "Astra" in tile.get_node("Caption").text:
		fail("personalized unlocked tile");return
	tile.pressed.emit()
	if not await wait_until(func():return selector._saved=="elathra" and selector._pending.is_empty()):
		fail("equip unlocked art");return
	if selector._displayed!="elathra" or selector.artwork.texture==null or menu._menu_dialogue_key!="elathra":
		fail("equipped artwork and dialogue");return
	print("PASS actual unlocked personalized gallery, equip art and dialogue")
	get_tree().quit(0)