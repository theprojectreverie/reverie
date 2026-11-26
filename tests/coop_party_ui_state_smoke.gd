extends SceneTree
var ok := true
func _initialize() -> void:
	call_deferred("_run")
func check(value: bool, label: String) -> void:
	print("PARTY_UI ", label, "=", value)
	ok = ok and value
func _run() -> void:
	var panel = load("res://scenes/online/coop_lobby_screen.tscn").instantiate()
	root.add_child(panel)
	await process_frame
	var content = panel.get_node("Center/Panel/Margins/Content")
	var create := content.get_node("CreateButton") as Button
	var join := content.get_node("JoinButton") as Button
	var leave := content.get_node("Actions/LeaveButton") as Button
	var copy := content.get_node("Actions/CopyInviteButton") as Button
	var enter := content.get_node("EnterButton") as Button
	var refresh := content.get_node("Actions/RefreshButton") as Button
	check(create != null and not create.disabled and join.disabled and leave.disabled and copy.disabled and enter.disabled,"empty_lobby")
	panel.invite_input.text = "abcdefghijklmnopqrst"
	panel.invite_input.text_changed.emit(panel.invite_input.text)
	check(not join.disabled,"valid_invite")
	panel._request_pending = true
	panel._update_controls()
	check(create.disabled and join.disabled and refresh.disabled and enter.disabled,"busy_controls")
	panel._request_pending = false
	panel._lobby_id = "qa-lobby"
	panel._region_id = "six_zone_royal_gardens"
	panel._invite_code = "abcdefghijklmnopqrst"
	panel._update_controls()
	check(create.disabled and join.disabled and not leave.disabled and not copy.disabled and enter.disabled,"active_lobby")
	panel._on_server_event({"type":"connected","playerId":"local"})
	panel._on_server_event({"type":"snapshot","members":[{"id":"remote","name":"Friend","role":"leader","region_id":"six_zone_royal_gate"}]})
	check(not panel._snapshot_verified and enter.disabled,"unverified_snapshot")
	panel._on_server_event({"type":"snapshot","members":[{"id":"local","name":"Local","role":"leader","region_id":"six_zone_royal_gate"},{"id":"remote","name":"Friend","role":"member","region_id":"six_zone_royal_gate"}]})
	check(panel._snapshot_verified and panel.members_label.text.contains("Royal Gate | PARTY 2/4"),"verified_roster")
	check(str(panel.region_input.get_item_metadata(panel.region_input.selected))=="six_zone_royal_gate","region_selector_sync")
	panel._on_server_event({"type":"region_transition","regionId":"six_zone_willow_fields"})
	check(panel.members_label.text.contains("Willow Fields"),"live_region")
	panel._on_lobby_result("leave",false,{"error":"network_or_server_error"})
	check(panel._lobby_id=="qa-lobby" and not leave.disabled,"failed_leave_preserves_lobby")
	panel._on_realtime_disconnected()
	check(not panel._snapshot_verified and enter.disabled,"disconnect_locks_entry")
	panel._on_lobby_result("leave",true,{"status":"left"})
	check(panel._lobby_id.is_empty() and not create.disabled and leave.disabled and copy.disabled,"confirmed_leave")
	panel.queue_free()
	await process_frame
	print("PARTY_UI_PASS=",ok)
	quit(0 if ok else 1)
