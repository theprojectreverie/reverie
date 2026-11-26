extends Node
## Local-only integration: real AuthGateway, CombatScreen, HTTP and server worker.
func _ready() -> void:
	call_deferred("_run")
func _run() -> void:
	var api := OS.get_environment("REVERIE_QA_API")
	if OS.get_environment("REVERIE_E2E_DISABLE_LOCAL_SAVE") != "1" or not api.begins_with("http://127.0.0.1:") or AuthGateway.is_authenticated():
		get_tree().quit(2)
		return
	AuthGateway.api_base_url = api
	var result: Error = AuthGateway.login(OS.get_environment("REVERIE_QA_NAME"), OS.get_environment("REVERIE_QA_PASSWORD"))
	if result != OK:
		_fail("login could not start")
		return
	var auth: Array = await AuthGateway.auth_result
	if not bool(auth[1]) or not AuthGateway.is_authenticated():
		_fail("QA login failed")
		return
	var marker := Node.new()
	marker.name = "StoryOpeningWorldSync"
	add_child(marker)
	var battle := (load("res://scenes/ui/combat_screen.tscn") as PackedScene).instantiate() as CombatScreen
	battle.group_id = "gerald_boss_encounter"
	add_child(battle)
	var deadline := Time.get_ticks_msec()+20000
	while is_instance_valid(battle) and battle.engine == null and Time.get_ticks_msec()<deadline:
		await get_tree().create_timer(0.05).timeout
	if not is_instance_valid(battle) or battle.engine == null or not battle._session_component.is_online_gerald():
		_fail("real server battle could not start")
		return
	print("PASS live authenticated battle initialized")
	for n in range(15):
		if battle._resolved:break
		if battle._animating:
			await get_tree().create_timer(0.2).timeout
			continue
		var actor := battle.engine.current_actor()
		var targets := battle.engine.living_indices(CombatEngine.ENEMY_TEAM)
		if actor == null or targets.is_empty():break
		await battle._session_component.execute_action(str(actor.skills[0]),[targets[0]])
	if not battle._resolved or not battle._session_component._spar_verified or int(battle._pending_rewards.get("gold",0))<=0:
		_fail("live fight did not produce verified victory")
		return
	print("PASS real combat HUD received settled victory")
	await battle._result_component.claim(true)
	await get_tree().process_frame
	if is_instance_valid(battle):
		_fail("result did not close")
		return
	await AudioDirector.drain_for_shutdown()
	print("GERALD_LIVE_CLIENT_PASS")
	get_tree().quit(0)
func _fail(reason: String) -> void:
	push_error("GERALD_LIVE_CLIENT_FAIL: "+reason)
	get_tree().quit(1)
