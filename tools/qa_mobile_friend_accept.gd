extends Node

func _ready():
	call_deferred("run")

func wait_for(check: Callable, seconds: float=20.0) -> bool:
	var end:=Time.get_ticks_msec()+int(seconds*1000)
	while not check.call():
		if Time.get_ticks_msec()>end:return false
		await get_tree().process_frame
	return true

func fail(message: String):
	push_error("MOBILE FRIEND QA: "+message)
	get_tree().quit(1)

func run():
	TouchInput.using_touch=true
	AuthGateway.api_base_url=OS.get_environment("QA_API")
	if AuthGateway.login(OS.get_environment("QA_NAME"),OS.get_environment("QA_PASSWORD"))!=OK:
		fail("login start");return
	var result=await AuthGateway.auth_result
	if not result[1]:fail("login");return
	var screen=load("res://scenes/ui/social_screen.tscn").instantiate()
	add_child(screen)
	if not await wait_for(func():return screen._friends.size()==1 and screen._operation.is_empty()):
		fail("pending request load");return
	await get_tree().process_frame
	var list:ScrollContainer=screen._layout.get_node("Scroll")
	if not list.visible or list.size.y<100.0 or screen._layout.get_node("Profile").visible:
		fail("mobile list size/profile mode");return
	var button:Button
	for child in list.get_node("Rows").get_child(0).get_children():
		if child is Button and child.text=="Accept":button=child
	if button==null or button.disabled or not button.is_visible_in_tree():
		fail("accept button unavailable");return
	if not list.get_global_rect().encloses(button.get_global_rect()):
		fail("accept button clipped");return
	# A tap during background refresh must be queued, not discarded.
	if not screen._begin("friends","/friends"):
		fail("refresh start");return
	if button.disabled:fail("accept disabled during refresh");return
	button.pressed.emit()
	if screen._queued_friend_action.is_empty():
		fail("accept not queued");return
	if not await wait_for(func():return screen._friends.size()==1 and screen._friends[0].status=="accepted" and screen._operation.is_empty()):
		fail("acceptance did not persist");return
	print("PASS mobile visible accept button, queued refresh action, live HTTPS acceptance")
	get_tree().quit()