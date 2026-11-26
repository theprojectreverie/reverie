extends Node
func _ready():
	call_deferred("run")

func wait_idle(screen:Control)->bool:
	var deadline:=Time.get_ticks_msec()+12000
	while not str(screen._operation).is_empty():
		if Time.get_ticks_msec()>deadline:return false
		await get_tree().process_frame
	return true

func fail(reason:String):
	print("FAIL ",reason)
	get_tree().quit(1)

func run():
	AuthGateway.api_base_url=OS.get_environment("QA_API")
	if AuthGateway.login(OS.get_environment("QA_NAME"),OS.get_environment("QA_PASSWORD"))!=OK:fail("login");return
	var auth=await AuthGateway.auth_result
	if not auth[1]:fail("auth");return
	var social=preload("res://scenes/ui/social_screen.tscn").instantiate()
	add_child(social)
	var deadline:=Time.get_ticks_msec()+12000
	while not social._profile_loaded or not social._operation.is_empty():
		if Time.get_ticks_msec()>deadline:fail("social load");return
		await get_tree().process_frame
	social._open_guilds()
	var screen=social.get_node_or_null("GuildScreen")
	if screen==null or social._shell.visible:fail("guild navigation");return
	if not await wait_idle(screen) or not screen._loaded:fail("guild initial load");return
	var name:=OS.get_environment("QA_GUILD")
	if OS.get_environment("QA_ROLE")=="A":
		screen._body.get_node("Editor/Name").text=name
		screen._body.get_node("Editor/Description").text="Local QA guild"
		screen._body.get_node("Editor/Emblem").select(1)
		screen._body.get_node("Editor/Save").pressed.emit()
		if not await wait_idle(screen) or screen._guild.is_empty() or screen._guild.role!="leader":fail("guild create "+str(screen._layout.get_node("Status").text));return
		deadline=Time.get_ticks_msec()+20000
		while screen._body.get_node("Requests").get_child_count()<2:
			if Time.get_ticks_msec()>deadline:fail("application not visible");return
			await get_tree().create_timer(0.5).timeout
			screen._layout.get_node("Toolbar/Refresh").pressed.emit()
			if not await wait_idle(screen):fail("refresh");return
		var request_row=screen._body.get_node("Requests").get_child(1)
		request_row.get_child(1).pressed.emit()
		if not await wait_idle(screen) or int(screen._guild.memberCount)!=2:fail("accept application");return
		print("PASS guild creation and approval using actual screen buttons")
	else:
		deadline=Time.get_ticks_msec()+20000
		screen._layout.get_node("Toolbar/Search").text=name
		while true:
			screen._layout.get_node("Toolbar/Find").pressed.emit()
			if not await wait_idle(screen):fail("search");return
			var rows=screen._body.get_node("Results")
			if rows.get_child_count()>=3 and rows.get_child(1) is HBoxContainer:
				rows.get_child(1).get_child(1).pressed.emit()
				break
			if Time.get_ticks_msec()>deadline:fail("guild search missing");return
			await get_tree().create_timer(0.5).timeout
		if not await wait_idle(screen):fail("apply");return
		deadline=Time.get_ticks_msec()+20000
		while screen._guild.is_empty():
			if Time.get_ticks_msec()>deadline:fail("join confirmation");return
			await get_tree().create_timer(0.5).timeout
			screen._layout.get_node("Toolbar/Refresh").pressed.emit()
			if not await wait_idle(screen):fail("membership refresh");return
		if screen._guild.role!="member" or int(screen._guild.memberCount)!=2:fail("member role");return
		print("PASS search, application, and joined membership")
	if OS.get_environment("QA_ROLE")=="A":
		var donate:Button=screen._body.get_node("Treasury/Donation/Donate")
		if donate.disabled:fail("donation unavailable");return
		donate.pressed.emit()
		var dialog:ConfirmationDialog=screen._layout.get_node("ConfirmAction")
		if not dialog.visible:fail("donation confirmation");return
		dialog.confirmed.emit()
		dialog.hide()
		if not await wait_idle(screen):fail("donation timeout");return
		if str(screen._treasury.get("gold",""))!="100" or int(screen._treasury.get("donatedToday",0))!=100:fail("donation state "+str(screen._treasury));return
		print("PASS treasury donation confirmation and updated balance")
	else:
		deadline=Time.get_ticks_msec()+12000
		while str(screen._treasury.get("gold",""))!="100":
			if Time.get_ticks_msec()>deadline:fail("shared treasury balance");return
			await get_tree().create_timer(0.4).timeout
			screen._layout.get_node("Toolbar/Refresh").pressed.emit()
			if not await wait_idle(screen):fail("treasury refresh");return
		print("PASS treasury balance visible to another member")
	var league:Button=screen._body.get_node("Competition/Open")
	if league.disabled or not league.is_visible_in_tree():fail("league control");return
	league.pressed.emit()
	if not await wait_idle(screen):fail("league load");return
	if not str(screen._body.get_node("Competition/Period").text).begins_with("Season:"):fail("league period");return
	if str(screen._body.get_node("Competition/Own").text)!="Your guild: unranked":fail("league own rank");return
	if screen._body.get_node("Competition/Rows").get_child_count()==0:fail("league rows");return
	print("PASS seasonal guild leaderboard opened through actual screen button")
	screen.close_screen()
	await get_tree().process_frame
	if not social._shell.visible:fail("return to social");return
	var chat=preload("res://scenes/ui/chat_screen.tscn").instantiate()
	add_child(chat)
	chat._layout.get_node("Channels/Guild").pressed.emit()
	deadline=Time.get_ticks_msec()+12000
	while chat._guild_id.is_empty() or not chat._operation.is_empty():
		if Time.get_ticks_msec()>deadline:fail("guild chat access");return
		await get_tree().process_frame
	var field:LineEdit=chat._layout.get_node("Composer/Message")
	var send:Button=chat._layout.get_node("Composer/Send")
	field.text="Guild QA "+OS.get_environment("QA_ROLE")
	send.pressed.emit()
	deadline=Time.get_ticks_msec()+12000
	while true:
		var contents:Array=[]
		for message in chat._last_messages:contents.append(message.text)
		if contents.has("Guild QA A") and contents.has("Guild QA B"):break
		if Time.get_ticks_msec()>deadline:fail("guild chat delivery "+str(chat._last_messages));return
		await get_tree().process_frame
	print("PASS guild chat button, send and two-way delivery")
	chat.close_screen()
	social.queue_free()
	await get_tree().process_frame
	AudioDirector.stop_all_audio_immediately()
	await get_tree().create_timer(0.5).timeout
	print("GUILD_CLIENT_PASS")
	get_tree().quit(0)