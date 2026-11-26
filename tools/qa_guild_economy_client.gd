extends Node

func _ready():
	call_deferred("run")

func fail(reason:String):
	print("FAIL ",reason)
	get_tree().quit(1)

func idle(screen:Control)->bool:
	var deadline:=Time.get_ticks_msec()+15000
	while not str(screen._operation).is_empty():
		if Time.get_ticks_msec()>deadline:return false
		await get_tree().process_frame
	await get_tree().process_frame
	return true

func find_button(rows:Node,caption:String)->Button:
	for row in rows.get_children():
		if row is HBoxContainer:
			for child in row.get_children():
				if child is Button and child.text==caption and not child.disabled:return child
	return null

func run():
	AuthGateway.api_base_url=OS.get_environment("QA_API")
	if AuthGateway.login(OS.get_environment("QA_NAME"),OS.get_environment("QA_PASSWORD"))!=OK:fail("login");return
	var auth=await AuthGateway.auth_result
	if not auth[1]:fail("auth");return
	var screen=preload("res://scenes/ui/guild_screen.tscn").instantiate()
	add_child(screen)
	if not await idle(screen) or screen._shop.is_empty():fail("shop unavailable");return
	var missions=screen._body.get_node("Progression/Missions")
	for i in range(3):
		var claim:=find_button(missions,"Claim")
		if claim==null:fail("mission unavailable");return
		claim.pressed.emit()
		if not await idle(screen):fail("mission timeout");return
	if str(screen._shop.balance)!="40":fail("mission tokens "+str(screen._shop));return
	print("PASS actual mission buttons award 40 guild tokens")
	var rows=screen._body.get_node("Shop/Rows")
	var buy:=find_button(rows,"Buy")
	if buy==null:fail("purchase unavailable");return
	buy.pressed.emit()
	var dialog:ConfirmationDialog=screen._layout.get_node("ConfirmAction")
	if not dialog.visible:fail("purchase confirmation");return
	dialog.confirmed.emit()
	dialog.hide()
	if not await idle(screen):fail("purchase timeout");return
	if str(screen._shop.balance)!="15" or int(screen._shop.offers[0].purchased)!=1:fail("purchase result "+str(screen._shop));return
	if find_button(rows,"Buy")!=null:fail("insufficient funds control");return
	print("PASS shop confirmation and updated stock and balance")
	var league=screen._body.get_node("Competition/Open")
	league.pressed.emit()
	if not await idle(screen):fail("league timeout");return
	var reward:=find_button(screen._body.get_node("Competition/Rows"),"Claim")
	if reward==null:fail("season reward missing");return
	reward.pressed.emit()
	if not await idle(screen):fail("reward timeout");return
	if find_button(screen._body.get_node("Competition/Rows"),"Claim")!=null:fail("repeat claim enabled");return
	var found:=false
	for row in screen._body.get_node("Competition/Rows").get_children():
		if row is HBoxContainer:
			for child in row.get_children():
				if child is Button and child.text=="Claimed" and child.disabled:found=true
	if not found:fail("claimed button missing");return
	if str(screen._shop.balance)!="315":fail("reward balance");return
	print("PASS seasonal claim control and refreshed token wallet")
	screen.close_screen()
	await get_tree().process_frame
	AudioDirector.stop_all_audio_immediately()
	await get_tree().create_timer(0.5).timeout
	print("GUILD_ECONOMY_CLIENT_PASS")
	get_tree().quit(0)
