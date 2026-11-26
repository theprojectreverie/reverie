extends Node
func _ready() -> void:
	call_deferred("run")
func fail(reason: String) -> void:
	print("FAIL ",reason)
	get_tree().quit(1)
func wait_until(check: Callable) -> bool:
	var deadline:=Time.get_ticks_msec()+12000
	while not check.call():
		if Time.get_ticks_msec()>deadline:return false
		await get_tree().process_frame
	return true
func run() -> void:
	AuthGateway.api_base_url=OS.get_environment("QA_API")
	var screen=load("res://scenes/online/account_screen.tscn").instantiate()
	add_child(screen)
	screen.email_login.text=OS.get_environment("QA_NAME")
	screen.password_login.text=OS.get_environment("QA_PASSWORD")
	screen._login()
	if not await wait_until(func():return screen._appeal_button.visible):
		fail("appeal button after denied sign-in");return
	if AuthGateway.is_authenticated():fail("suspended session");return
	screen._appeal_button.pressed.emit()
	if not screen._appeal_dialog.visible:fail("dialog");return
	screen._appeal_statement.text="Please review this suspension"
	screen._appeal_dialog.confirmed.emit()
	screen._appeal_dialog.hide()
	if not await wait_until(func():return screen.login_status.text.begins_with("Appeal: Pending")):
		fail("appeal confirmation");return
	if AuthGateway.is_authenticated() or screen._appeal_button.visible:fail("no gameplay or duplicate button");return
	screen._login()
	if not await wait_until(func():return screen.login_status.text.contains("Appeal: Pending")):
		fail("persistent pending status");return
	print("PASS Godot suspension login, appeal dialog, submit and persistent status")
	screen.queue_free()
	await get_tree().process_frame
	get_tree().quit(0)