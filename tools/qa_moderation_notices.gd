extends Node
func _ready() -> void:
	call_deferred("run")
func fail(reason: String) -> void:
	print("FAIL ",reason)
	get_tree().quit(1)
func wait_until(check: Callable,seconds: float=12.0) -> bool:
	var deadline:=Time.get_ticks_msec()+int(seconds*1000)
	while not check.call():
		if Time.get_ticks_msec()>deadline:return false
		await get_tree().process_frame
	return true
func run() -> void:
	AuthGateway.api_base_url=OS.get_environment("QA_API")
	if AuthGateway.login(OS.get_environment("QA_NAME"),OS.get_environment("QA_PASSWORD"))!=OK:
		fail("login");return
	var auth=await AuthGateway.auth_result
	if not auth[1]:fail("auth");return
	var screen=load("res://scenes/ui/chat_screen.tscn").instantiate()
	add_child(screen)
	if not await wait_until(func():return screen._notice_unread==2 and screen._notice_op.is_empty()):
		fail("initial notice load");return
	if screen._mute_deadline<=Time.get_ticks_msec() or not screen._layout.get_node("Composer/Send").disabled:
		fail("mute composer state");return
	if screen._layout.get_node("Moderation/Notices").text!="Notices (2)":
		fail("badge");return
	screen._layout.get_node("Moderation/Notices").pressed.emit()
	if not screen._notice_dialog.visible or screen._notice_shown_ids.size()!=2:
		fail("dialog");return
	var body: String=screen._notice_dialog.get_node("History").get_parsed_text()
	if not "QA reason for moderation" in body or not "Until " in body:
		fail("reason and expiry");return
	screen._notice_dialog.confirmed.emit()
	screen._notice_dialog.hide()
	if not await wait_until(func():return screen._notice_unread==0 and screen._notice_op.is_empty()):
		fail("read confirmation");return
	screen.queue_free()
	await get_tree().process_frame
	var reopened=load("res://scenes/ui/chat_screen.tscn").instantiate()
	add_child(reopened)
	if not await wait_until(func():return reopened._notice_rows.size()==2 and reopened._notice_op.is_empty()):
		fail("reload");return
	if reopened._notice_unread!=0 or reopened._mute_deadline<=Time.get_ticks_msec():
		fail("persistent read state or mute");return
	print("PASS Godot notice badge, reason, mute countdown, read confirmation and reopen")
	reopened.queue_free()
	await get_tree().process_frame
	get_tree().quit(0)