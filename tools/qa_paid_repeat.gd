extends Node

func _ready() -> void:
	call_deferred("run")

func fail(reason: String) -> void:
	printerr("FAIL ", reason)
	get_tree().quit(1)

func run() -> void:
	AuthGateway.api_base_url = OS.get_environment("QA_API")
	if AuthGateway.login(OS.get_environment("QA_NAME"), OS.get_environment("QA_PASSWORD")) != OK:
		fail("login start"); return
	var auth: Array = await AuthGateway.auth_result
	if not auth[1]:
		fail("login"); return
	var scene: GachaScreen = load("res://scenes/ui/gacha_screen.tscn").instantiate()
	add_child(scene)
	await get_tree().process_frame
	await scene._toggle_online(true)
	if OS.get_environment("QA_PAID_STAGE") == "first":
		if scene.paid_summon_progress() != 70 or scene.summon_currency("paid_moonstones") != 3600:
			fail("first process initial progress"); return
		var pre: Dictionary = await scene._summon_flow.pull_online(scene._selected_banner,10,"paid_moonstones")
		if not pre.get("ok",false) or scene.paid_summon_progress() != 80:
			fail("first process paid summon"); return
		AuthGateway.logout()
		if not scene._summon_flow.online_state.is_empty() or scene.paid_guarantee_verified():
			fail("logout retained counter"); return
		print("PASS first independent Godot session: 70 to 80 paid pulls, logout clears private progress")
		scene.queue_free()
		await get_tree().process_frame
		await AudioDirector.drain_for_shutdown()
		get_tree().quit(0)
		return
	if scene.summon_currency("paid_moonstones") != 2400 or scene.paid_summon_progress() != 80:
		fail("initial paid wallet or progress"); return
	var first: Dictionary = await scene._summon_flow.pull_online(scene._selected_banner, 10, "paid_moonstones")
	if not first.get("ok", false) or scene.paid_summon_progress() != 90:
		fail("first paid pull"); return
	print("PASS second independent Godot session recovered 80 paid pulls")
	AuthGateway.logout()
	if not scene._summon_flow.online_state.is_empty() or scene.paid_guarantee_verified():
		fail("logout retained progress"); return
	if AuthGateway.login(OS.get_environment("QA_NAME"),OS.get_environment("QA_PASSWORD")) != OK:
		fail("second login start"); return
	var relogin: Array = await AuthGateway.auth_result
	while str(relogin[0]) != "login":
		relogin = await AuthGateway.auth_result
	if not relogin[1]:
		fail("second login"); return
	await scene._toggle_online(true)
	if scene.paid_summon_progress() != 90 or scene.summon_currency("paid_moonstones") != 1200:
		fail("relogin lost progress"); return
	var base_url := AuthGateway.api_base_url
	AuthGateway.api_base_url = "http://127.0.0.1:1"
	var unavailable: bool = await scene._summon_flow.refresh_online_state()
	if unavailable or scene.paid_guarantee_verified() or scene.summon_available(10,1200,"paid_moonstones"):
		fail("disconnected paid summon was enabled"); return
	AuthGateway.api_base_url = base_url
	await scene._toggle_online(true)
	if scene.paid_summon_progress() != 90 or not scene.paid_guarantee_verified():
		fail("reconnection lost progress"); return
	scene._summon_flow.online_state.erase("paidGuaranteePolicy")
	if scene.summon_available(10,1200,"paid_moonstones"):
		fail("old server policy accepted"); return
	var blocked: Dictionary = await scene._summon_flow.pull_online(scene._selected_banner,10,"paid_moonstones")
	if blocked.get("ok",false) or not scene._summon_flow.pending_online.is_empty():
		fail("unverified paid request created"); return
	await scene._toggle_online(true)
	if not scene.paid_guarantee_verified() or scene.paid_summon_progress() != 90:
		fail("policy recovery"); return
	print("PASS logout/relogin, network interruption/reconnect, and unsupported server policy lock")
	# Simulate a stale client snapshot without altering server records.
	scene._summon_flow.online_state["paidTotal"] = "80"
	var stale: Dictionary = await scene._summon_flow.pull_online(scene._selected_banner,10,"paid_moonstones")
	if stale.get("ok",false) or not str(stale.get("error","")).contains("another session"):
		fail("stale paid request not rejected"); return
	if not scene._summon_flow.pending_online.is_empty() or str(scene._summon_flow.online_state.get("paidTotal","")) != "90" or scene.paid_summon_progress() != 90 or scene.summon_currency("paid_moonstones") != 1200:
		fail("stale counter recovery"); return
	print("PASS actual Godot stale paid snapshot refresh with no charge")
	scene._summon_flow.show_results(first.results, "paid_moonstones", scene._selected_banner)
	var again: Button = scene._results_layer.get_node("Center/Panel/Content/Footer/SummonAgainButton")
	if again.disabled or again.text != "Paid x10 Again":
		fail("paid repeat button: " + again.text); return
	again.pressed.emit()
	var deadline := Time.get_ticks_msec() + 12000
	while scene._summon_busy and Time.get_ticks_msec() < deadline:
		if is_instance_valid(scene._results_layer) and scene._results_layer is SummonRevealOverlay:
			scene._results_layer.skip_all()
		await get_tree().create_timer(0.1).timeout
	if scene._summon_busy or scene.summon_currency("paid_moonstones") != 0 or scene.summon_currency("crystals") != 1200 or scene.paid_summon_progress() != 0:
		fail("repeat did not preserve paid currency or reset guarantee"); return
	if not is_instance_valid(scene._results_layer):
		fail("result overlay missing"); return
	again = scene._results_layer.get_node("Center/Panel/Content/Footer/SummonAgainButton")
	if not again.disabled:
		fail("repeat enabled with empty paid wallet"); return
	var grid: GridContainer = scene._results_layer.get_node("Center/Panel/Content/ResultsScroll/ResultGrid")
	var status: Label = grid.get_child(0).get_node("Content/Status")
	if not status.text.contains("PAID MILESTONE") or not status.text.contains("FEATURED"):
		fail("guaranteed reward not highlighted: " + status.text); return
	print("PASS actual Godot paid repeat currency, 100-pull milestone, result highlight, empty wallet, free currency untouched")
	scene._results_layer.queue_free()
	scene._results_layer = null
	var history: AcceptDialog = scene.get_node("SummonHistoryDialog")
	scene._history_button.pressed.emit()
	var history_deadline := Time.get_ticks_msec() + 8000
	while history.get("_busy") and Time.get_ticks_msec() < history_deadline:
		await get_tree().process_frame
	if not history.visible or history.get_node("Body/Scroll/Entries").get_child_count() != 10:
		fail("history dialog entries"); return
	var text_found := false
	for label in history.get_node("Body/Scroll/Entries").find_children("*", "Label", true, false):
		if label.text.contains("PAID MILESTONE - FEATURED"):
			text_found = true
	if not text_found:
		fail("history featured marker"); return
	var filter: OptionButton = history.get_node("Body/Filters/Currency")
	filter.select(2)
	filter.item_selected.emit(2)
	while history.get("_busy") and Time.get_ticks_msec() < history_deadline:
		await get_tree().process_frame
	if history.get_node("Body/Scroll/Entries").get_child_count() != 1 or not history.get_node("Body/Scroll/Entries").get_child(0).text.contains("No recorded"):
		fail("history free filter"); return
	print("PASS actual Godot summon history dialog, entries, paid marker and empty crystal filter")
	filter.select(3)
	filter.item_selected.emit(3)
	while history.get("_busy") and Time.get_ticks_msec() < history_deadline:
		await get_tree().process_frame
	if not history.get_node("Body/Summary").text.contains("100 recorded paid summons"):
		fail("audit summary"); return
	var audit_found := false
	for label in history.get_node("Body/Scroll/Entries").find_children("*","Label",true,false):
		if label.text.contains("Featured reward recorded"):
			audit_found = true
	if not audit_found:
		fail("audit reward"); return
	print("PASS Godot guarantee audit view")
	history.hide()
	history._invalidate()
	scene.queue_free()
	await get_tree().process_frame
	await AudioDirector.drain_for_shutdown()
	get_tree().quit(0)
