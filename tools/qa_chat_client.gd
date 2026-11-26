extends Node
func _ready():
	call_deferred("run")
func fail(reason: String):
	print("FAIL ",reason)
	get_tree().quit(1)
func run():
	var private_alerts: Array[String]=[]
	EventBus.toast_requested.connect(func(message: String):
		if message=="New private message" or message.ends_with("new private messages"):private_alerts.append(message))
	AuthGateway.api_base_url=OS.get_environment("QA_API")
	if AuthGateway.login(OS.get_environment("QA_NAME"),OS.get_environment("QA_PASSWORD"))!=OK:
		fail("login")
		return
	var auth=await AuthGateway.auth_result
	if not auth[1]:
		fail("auth")
		return
	GameState.quest_domain.flags["tutorial_complete"]=true
	var zone=load("res://scenes/world/six_zone_reverie/individual_zones/zone_02_royal_gate_standalone.tscn" if OS.get_environment("QA_ROLE")=="A" else "res://scenes/world/six_zone_reverie/individual_zones/zone_03_willow_fields_standalone.tscn").instantiate()
	add_child(zone)
	await get_tree().process_frame
	var hud=zone.get_node("UI/HUD")
	if OS.get_environment("QA_ROLE")=="B":
		var badge_deadline=Time.get_ticks_msec()+10000
		while AuthGateway.unread_private_messages!=1:
			if Time.get_ticks_msec()>badge_deadline:fail("offline unread badge");return
			await get_tree().process_frame
		if hud.get_node("ActionStack/ChatButton").text!="CHAT (1)":fail("HUD unread text");return
		if private_alerts.is_empty():fail("private message notification");return
	hud.get_node("ActionStack/ChatButton").pressed.emit()
	await get_tree().process_frame
	var router=zone.get_node("OverlayRouter")
	var screen=router.active_overlay
	if screen==null or zone.checkpoint_player.input_enabled:
		fail("chat HUD navigation or input suspension")
		return
	var field=screen._layout.get_node("Composer/Message")
	var send=screen._layout.get_node("Composer/Send")
	var deadline=Time.get_ticks_msec()+10000
	while not screen._operation.is_empty() or send.disabled:
		if Time.get_ticks_msec()>deadline:
			fail("chat not ready")
			return
		await get_tree().process_frame
	field.text="QA "+OS.get_environment("QA_ROLE")+" [b]literal[/b]"
	send.pressed.emit()
	while field.text!="" or _normal_count(screen._last_messages)<2:
		if Time.get_ticks_msec()>deadline:
			fail("world messages not received "+str(screen._last_messages))
			return
		await get_tree().process_frame
	var contents: Array=[]
	for m in screen._last_messages:contents.append(m.text)
	if not contents.has("QA A [b]literal[/b]") or not contents.has("QA B [b]literal[/b]"):
		fail("world messages missing")
		return
	print("PASS cross-zone actual Chat button, send, receive, literal markup and movement lock")
	deadline=Time.get_ticks_msec()+15000
	while send.disabled:
		if Time.get_ticks_msec()>deadline:fail("sticker composer not ready");return
		await get_tree().process_frame
	field.text="Draft remains"
	screen._layout.get_node("Composer/Emotes").pressed.emit()
	screen._emote_tab(true)
	var sticker_grid=screen._layout.get_node("EmotePicker/StickerScroll/StickerGrid")
	sticker_grid.get_child(0 if OS.get_environment("QA_ROLE")=="A" else 4).pressed.emit()
	while _normal_count(screen._last_messages)<4 or not screen._operation.is_empty():
		if Time.get_ticks_msec()>deadline:fail("world sticker delivery "+str(screen._last_messages));return
		await get_tree().process_frame
	var sticker_messages: Array=[]
	for m in screen._last_messages:sticker_messages.append(m.text)
	if not sticker_messages.has("[sticker:lilith_ghost_plush]") or not sticker_messages.has("[sticker:gerald_chibi]"):fail("world sticker tokens");return
	if field.text!="Draft remains":fail("sticker cleared draft");return
	var history: RichTextLabel=screen._layout.get_node("History")
	if history.get_parsed_text().contains("[sticker:"):fail("sticker rendered as plain token");return
	while send.disabled:
		if Time.get_ticks_msec()>deadline:fail("emoji composer not ready");return
		await get_tree().process_frame
	field.text="Emoji "+OS.get_environment("QA_ROLE")+" "
	field.caret_column=field.text.length()
	screen._insert_emoji(String.chr(0x1F600))
	send.pressed.emit()
	while _normal_count(screen._last_messages)<6 or field.text!="":
		if Time.get_ticks_msec()>deadline:fail("world emoji delivery");return
		await get_tree().process_frame
	var emoji_messages: Array=[]
	for m in screen._last_messages:emoji_messages.append(m.text)
	if not emoji_messages.has("Emoji A "+String.chr(0x1F600)) or not emoji_messages.has("Emoji B "+String.chr(0x1F600)):fail("emoji round trip");return
	print("PASS both Godot clients exchanged stickers and emoji; draft preserved")
	deadline=Time.get_ticks_msec()+15000
	while send.disabled:
		if Time.get_ticks_msec()>deadline:fail("reply composer");return
		await get_tree().process_frame
	var parent_id: String=""
	for m in screen._last_messages:
		if m.text==("[sticker:gerald_chibi]" if OS.get_environment("QA_ROLE")=="A" else "[sticker:lilith_ghost_plush]"):parent_id=str(m.id)
	if parent_id.is_empty():fail("reply target");return
	history.meta_clicked.emit("reply:"+parent_id)
	if not screen._layout.get_node("ReplyBar").visible:fail("reply bar");return
	field.text="Reply QA "+OS.get_environment("QA_ROLE")
	send.pressed.emit()
	while _normal_count(screen._last_messages)<8 or field.text!="":
		if Time.get_ticks_msec()>deadline:fail("world reply delivery");return
		await get_tree().process_frame
	var replies=0
	for m in screen._last_messages:
		if str(m.text).begins_with("Reply QA ") and str(m.get("replyTo","")).length()==36:replies+=1
	if replies!=2 or not history.get_parsed_text().contains("Reply to "):fail("world reply references");return
	if screen._layout.get_node("ReplyBar").visible:fail("reply bar not cleared");return
	print("PASS world replies to stickers, both clients")
	screen._select("party")
	while not str(screen._layout.get_node("Status").text).contains("Join a party"):
		if Time.get_ticks_msec()>deadline+5000:
			fail("party guest feedback")
			return
		await get_tree().process_frame
	screen._layout.get_node("Channels/Private").pressed.emit()
	deadline=Time.get_ticks_msec()+18000
	var contacts=screen._layout.get_node("Contacts")
	while not screen._contacts_loaded or not screen._operation.is_empty():
		if Time.get_ticks_msec()>deadline:fail("private contacts");return
		await get_tree().process_frame
	if contacts.item_count!=2:fail("friend selector count");return
	if not contacts.get_item_text(1).contains(" - Online"):fail("online friend in chat contacts");return
	contacts.select(1)
	contacts.item_selected.emit(1)
	await get_tree().create_timer(1.2).timeout
	while send.disabled:
		if Time.get_ticks_msec()>deadline:fail("private composer");return
		await get_tree().process_frame
	field.text="Private QA "+OS.get_environment("QA_ROLE")
	send.pressed.emit()
	while field.text!="" or screen._last_messages.size()<3:
		if Time.get_ticks_msec()>deadline:fail("private delivery "+str(screen._last_messages)+" status="+str(screen._layout.get_node("Status").text)+" field="+field.text+" recipient="+screen._recipient+" operation="+screen._operation);return
		await get_tree().process_frame
	var private_contents: Array=[]
	for m in screen._last_messages:private_contents.append(m.text)
	if not private_contents.has("Private QA A") or not private_contents.has("Private QA B"):fail("private content");return
	if not private_contents.has("Offline delivery QA"):fail("offline history");return
	AuthGateway.refresh_social_summary()
	var unread_deadline=Time.get_ticks_msec()+12000
	while AuthGateway.unread_private_messages!=0:
		if Time.get_ticks_msec()>unread_deadline:fail("unread clear");return
		await get_tree().process_frame
	if hud.get_node("ActionStack/ChatButton").text!="CHAT":fail("HUD badge clear");return
	print("PASS private friend selector, offline history, unread badges and two-way delivery")
	deadline=Time.get_ticks_msec()+18000
	while send.disabled:
		if Time.get_ticks_msec()>deadline:fail("private sticker composer");return
		await get_tree().process_frame
	screen._send_sticker("revienna_fallen_matron" if OS.get_environment("QA_ROLE")=="A" else "lilith_playful")
	while screen._last_messages.size()<5:
		if Time.get_ticks_msec()>deadline:fail("private sticker delivery");return
		await get_tree().process_frame
	var private_stickers: Array=[]
	for m in screen._last_messages:private_stickers.append(m.text)
	if not private_stickers.has("[sticker:revienna_fallen_matron]") or not private_stickers.has("[sticker:lilith_playful]"):fail("private sticker content");return
	if history.get_parsed_text().contains("[sticker:"):fail("private sticker rendered as text");return
	print("PASS two-way private sticker delivery and rendering")
	deadline=Time.get_ticks_msec()+15000
	while send.disabled:
		if Time.get_ticks_msec()>deadline:fail("private reply composer");return
		await get_tree().process_frame
	var private_parent: String=""
	for m in screen._last_messages:
		if m.text=="Offline delivery QA":private_parent=str(m.id)
	screen._reply_clicked("reply:"+private_parent)
	field.text="Private reply "+OS.get_environment("QA_ROLE")
	send.pressed.emit()
	while screen._last_messages.size()<7 or field.text!="":
		if Time.get_ticks_msec()>deadline:fail("private reply delivery");return
		await get_tree().process_frame
	var private_replies=0
	for m in screen._last_messages:
		if str(m.text).begins_with("Private reply ") and str(m.get("replyTo",""))==private_parent:private_replies+=1
	if private_replies!=2:fail("private reply references");return
	print("PASS private reply references persisted and delivered")
	deadline=Time.get_ticks_msec()+12000
	while not screen._operation.is_empty():
		if Time.get_ticks_msec()>deadline:fail("profile request busy");return
		await get_tree().process_frame
	screen._layout.get_node("PlayerActions/Profile").pressed.emit()
	while not screen._profile_access:
		if Time.get_ticks_msec()>deadline:fail("profile inspection "+screen._profile_content().get_node("Status").text);return
		await get_tree().process_frame
	if not screen._profile_card.visible or not screen._profile_content().get_node("Stats").text.contains("Level"):fail("friend profile data");return
	if screen._profile_content().get_node("Invite").disabled:fail("invite button disabled");return
	screen._profile_content().get_node("Invite").pressed.emit()
	while not screen._operation.is_empty():
		if Time.get_ticks_msec()>deadline:fail("invite request");return
		await get_tree().process_frame
	if not screen._profile_content().get_node("Status").text.contains("Create or lead a party first"):fail("no party feedback "+screen._profile_content().get_node("Status").text);return
	if OS.get_environment("QA_ROLE")=="A":
		var req:=HTTPRequest.new()
		add_child(req)
		var headers:=PackedStringArray(["Authorization: Bearer "+AuthGateway.access_token_for_request(),"Content-Type: application/json"])
		if req.request(AuthGateway.api_base_url+"/v1/co-op/lobbies",headers,HTTPClient.METHOD_POST,JSON.stringify({"regionId":"six_zone_willow_fields","maxMembers":4}))!=OK:fail("create party request");return
		var response: Array=await req.request_completed
		req.queue_free()
		if int(response[1])!=201:fail("create party "+str(response[1]));return
		while not screen._operation.is_empty():await get_tree().process_frame
		screen._profile_content().get_node("Invite").pressed.emit()
		while not screen._operation.is_empty():
			if Time.get_ticks_msec()>deadline:fail("send invitation timeout");return
			await get_tree().process_frame
		if not screen._profile_content().get_node("Status").text.contains("Party invitation sent"):fail("invite confirmation "+screen._profile_content().get_node("Status").text);return
		print("PASS chat profile and direct party invitation")
	screen._profile_content().get_node("Header/Close").pressed.emit()
	if screen._profile_card.visible or not screen._profile_target.is_empty():fail("profile close");return
	print("PASS private friend profile inspection and invite restrictions")
	screen.close_screen()
	await get_tree().process_frame
	if not zone.checkpoint_player.input_enabled:
		fail("movement not restored")
		return
	print("PASS party access feedback and movement restored")
	zone.queue_free()
	for i in range(3):await get_tree().process_frame
	AudioDirector.stop_all_audio_immediately()
	await get_tree().create_timer(0.35).timeout
	get_tree().quit(0)

func _normal_count(messages: Array) -> int:
	var count:=0
	for message in messages:
		if str(message.get("kind",""))!="mythic_summon" and str(message.get("name","")) in [OS.get_environment("QA_NAME"),OS.get_environment("QA_PEER_NAME")]:count+=1
	return count
