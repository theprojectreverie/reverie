extends Node

func _ready() -> void:
	call_deferred("run")

func fail(message: String) -> void:
	printerr("FAIL ",message)
	get_tree().quit(1)

func run() -> void:
	if OS.get_environment("REVERIE_E2E_DISABLE_LOCAL_SAVE") != "1":
		fail("fixture only"); return
	AuthGateway.api_base_url = OS.get_environment("QA_API")
	if AuthGateway.login(OS.get_environment("QA_NAME"),OS.get_environment("QA_PASSWORD")) != OK:
		fail("login start"); return
	var auth: Array = await AuthGateway.auth_result
	if not auth[1]:
		fail("login"); return
	var scene: GachaScreen = load("res://scenes/ui/gacha_screen.tscn").instantiate()
	add_child(scene)
	await get_tree().process_frame
	await scene._toggle_online(true)
	var flow := scene._summon_flow
	if OS.get_environment("QA_INTERRUPTED_STAGE") == "drop":
		if scene.paid_summon_progress()!=90 or scene.summon_currency("paid_moonstones")!=1200:
			fail("initial counter"); return
		var outcome: Dictionary = await flow.pull_online(scene._selected_banner,10,"paid_moonstones")
		if outcome.get("ok",false) or flow.pending_online.is_empty() or not FileAccess.file_exists(flow._journal_path()):
			fail("interrupted request was not preserved"); return
		print("PASS network loss retains original paid request in durable journal")
	else:
		if scene.paid_summon_progress()!=0 or scene.summon_currency("paid_moonstones")!=0 or flow.pending_online.is_empty():
			fail("committed result or journal not recovered"); return
		var banner := str(flow.pending_online.bannerId)
		for other in ContentDB.banners.keys():
			if str(other)!=banner:
				scene._select_banner(str(other))
				break
		if not scene._pending_recovery.visible or scene._pending_recovery.disabled:
			fail("recovery unavailable with empty wallet or another banner selected"); return
		scene._pending_recovery.pressed.emit()
		var deadline := Time.get_ticks_msec()+12000
		while scene._summon_busy and Time.get_ticks_msec()<deadline:
			if is_instance_valid(scene._results_layer) and scene._results_layer is SummonRevealOverlay:
				scene._results_layer.skip_all()
			await get_tree().create_timer(0.1).timeout
		if scene._summon_busy or not flow.pending_online.is_empty() or scene._selected_banner!=banner or scene.summon_currency("paid_moonstones")!=0 or scene.summon_currency("crystals")!=1200:
			fail("recovery changed currency or did not clear journal"); return
		if not is_instance_valid(scene._results_layer):
			fail("replayed result missing"); return
		var grid: GridContainer = scene._results_layer.get_node("Center/Panel/Content/ResultsScroll/ResultGrid")
		var status: Label = grid.get_child(0).get_node("Content/Status")
		if not status.text.contains("PAID MILESTONE") or not status.text.contains("FEATURED"):
			fail("recovered featured milestone missing"); return
		if scene._pending_recovery.visible:
			fail("recovery button remains after success"); return
		print("PASS fresh Godot process recovered original featured reward through visible recovery button with zero paid balance")
		DirAccess.remove_absolute(ProjectSettings.globalize_path(flow._journal_path()))
	scene.queue_free()
	await get_tree().process_frame
	await AudioDirector.drain_for_shutdown()
	get_tree().quit(0)
