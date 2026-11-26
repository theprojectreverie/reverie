extends Node
func _ready():call_deferred("run")
func fail(reason:String):
	print("FAIL ",reason)
	get_tree().quit(1)
func wait_until(check:Callable,seconds:float=12.0)->bool:
	var deadline=Time.get_ticks_msec()+int(seconds*1000)
	while not check.call():
		if Time.get_ticks_msec()>deadline:return false
		await get_tree().process_frame
	return true
func run():
	AuthGateway.api_base_url=OS.get_environment("QA_API")
	CoopGateway.api_base_url=AuthGateway.api_base_url
	if AuthGateway.login(OS.get_environment("QA_NAME"),OS.get_environment("QA_PASSWORD"))!=OK:
		fail("login");return
	var auth=await AuthGateway.auth_result
	if not auth[1]:fail("auth");return
	GameState.quest_domain.flags["tutorial_complete"]=true
	var zone=load("res://scenes/world/six_zone_reverie/individual_zones/zone_02_royal_gate_standalone.tscn").instantiate()
	add_child(zone)
	await get_tree().process_frame
	zone.get_node("UI/HUD/ActionStack/SocialButton").pressed.emit()
	await get_tree().process_frame
	var screen=zone.get_node("OverlayRouter").active_overlay
	if screen==null or zone.checkpoint_player.input_enabled:fail("open friends");return
	if not await wait_until(func():return screen._profile_loaded and screen._operation.is_empty()):fail("profile loading");return
	var options=screen._layout.get_node("Profile/Pictures")
	var current_catalog:Array=[]
	for i in range(options.item_count):current_catalog.append(str(options.get_item_metadata(i)))
	for required in ["kael_avatar","gerald","lilith","ravienna","gerald_mythic","ravienna_mythic"]:
		if not current_catalog.has(required):fail("missing authored portrait "+required);return
	if current_catalog.size()!=37:fail("current portrait catalog count "+str(current_catalog.size()));return
	var role=OS.get_environment("QA_ROLE")
	var selected="lilith" if role=="A" else "gerald"
	for i in range(options.item_count):
		if options.get_item_metadata(i)==selected:
			options.select(i)
			options.item_selected.emit(i)
	if screen._layout.get_node("Profile/Save").disabled:fail("save disabled");return
	screen._layout.get_node("Profile/Save").pressed.emit()
	if not await wait_until(func():return screen._operation.is_empty() and screen._layout.get_node("Status").text=="Profile picture saved."):fail("save picture");return
	if screen._layout.get_node("Profile/Portrait").texture==null:fail("portrait texture");return
	if AuthGateway.current_player().get("avatar")!=selected:fail("account portrait cache");return
	var menu=load("res://scenes/ui/main_menu.tscn").instantiate()
	add_child(menu)
	await get_tree().process_frame
	var avatar=menu.get_node("ReferenceInterface/TopProfile/ProfileRow/AvatarFrame/KaelAvatar")
	if avatar.texture==null or avatar.texture != preload("res://scripts/ui/social_portrait.gd").texture(selected):fail("main menu portrait");return
	var calendar=menu.get_node("ReferenceInterface/LeftRail/CalendarButton")
	var saved_daily: Dictionary=GameState.daily_rewards.duplicate(true)
	GameState.daily_rewards={}
	menu._refresh_menu_notifications()
	if not calendar.get_node("Notification").visible:fail("daily dot missing");return
	calendar.pressed.emit()
	await get_tree().process_frame
	var reward_panel=menu.get_node_or_null("DailyRewardsOverlay")
	if reward_panel==null or reward_panel.claim_button.disabled:fail("daily overlay");return
	# Test the claimed state without spending or changing the player's saved wallet.
	GameState.daily_rewards={"last_claim_date":GameState.daily_reward_status().today}
	menu._refresh_menu_notifications()
	if calendar.get_node("Notification").visible:fail("daily dot remained after claim");return
	GameState.daily_rewards=saved_daily
	reward_panel.close_button.pressed.emit()
	await get_tree().process_frame
	var friends_button=menu.get_node("ReferenceInterface/LeftRail/FriendsButton")
	var chat_button=menu.get_node("ReferenceInterface/BottomNavigation/CommunicationButton")
	menu._on_friend_notification(3)
	menu._on_chat_notification(5)
	if not friends_button.get_node("Notification").visible or friends_button.get_node("Notification/Count").text!="3":fail("main menu friends badge");return
	if not chat_button.get_node("Notification").visible or chat_button.get_node("Notification/Count").text!="5":fail("main menu chat badge");return
	friends_button.pressed.emit()
	await get_tree().process_frame
	var friends_overlay=menu.get_node_or_null("PlayerProfileOverlay")
	if friends_overlay==null:fail("main menu friends shortcut");return
	friends_overlay.close_screen()
	await get_tree().process_frame
	chat_button.pressed.emit()
	await get_tree().process_frame
	var menu_chat=menu.get_node_or_null("PlayerProfileOverlay")
	if menu_chat==null or menu_chat._channel!="private":fail("main menu chat shortcut");return
	menu_chat.close_screen()
	await get_tree().process_frame
	print("PASS main-menu daily notification, friends and chat shortcuts")
	menu.queue_free()
	if role=="A":
		screen._layout.get_node("Search/Name").text=OS.get_environment("QA_OTHER")
		if not await wait_until(func():return screen._operation.is_empty()):fail("search busy");return
		screen._layout.get_node("Search/Find").pressed.emit()
		if not await wait_until(func():return not screen._found.is_empty() and screen._operation.is_empty()):fail("find friend");return
		if not screen._layout.get_node("Result/Portrait").visible or screen._layout.get_node("Result/Portrait").texture==null:fail("search portrait");return
		screen._layout.get_node("Search/Name").text_changed.emit("changed")
		if not screen._found.is_empty() or not screen._layout.get_node("Result/Add").disabled:fail("stale result");return
		screen._layout.get_node("Search/Find").pressed.emit()
		if not await wait_until(func():return not screen._found.is_empty() and screen._operation.is_empty()):fail("find again");return
		screen._layout.get_node("Result/Add").pressed.emit()
	else:
		if not await wait_until(func():return screen._friends.size()==1 and screen._friends[0].status=="pending" and screen._operation.is_empty(),18.0):fail("incoming request");return
		AuthGateway.refresh_social_summary()
		if not await wait_until(func():return AuthGateway.incoming_friend_requests==1):fail("incoming badge");return
		if zone.get_node("UI/HUD/ActionStack/SocialButton").text!="FRIENDS (1)":fail("badge label");return
		var row=screen._layout.get_node("Scroll/Rows").get_child(0)
		for button in row.get_children():
			if button is Button and button.text=="Accept":button.pressed.emit()
	if not await wait_until(func():return screen._friends.size()==1 and screen._friends[0].status=="accepted",18.0):fail("acceptance");return
	if not await wait_until(func():return screen._operation.is_empty()):fail("busy after acceptance");return
	AuthGateway.refresh_social_summary()
	if not await wait_until(func():return AuthGateway.incoming_friend_requests==0):fail("badge clear");return
	if not screen._friends[0].get("online",false):fail("online friend");return
	screen._layout.get_node("Search/Name").text=OS.get_environment("QA_OTHER")
	screen._layout.get_node("Search/Find").pressed.emit()
	if not await wait_until(func():return not screen._found.is_empty() and screen._operation.is_empty()):fail("search existing friend");return
	if not screen._layout.get_node("Result/Add").disabled or screen._layout.get_node("Result/Add").text!="Already friends":fail("existing friend action");return
	print("PASS ",role," actual profile picture, all authored options, accepted friendship, duplicate prevention")
	var inspect_row=screen._layout.get_node("Scroll/Rows").get_child(0)
	for button in inspect_row.get_children():
		if button is Button and button.text=="Profile":button.pressed.emit()
	var details=screen._layout.get_node("FriendProfile/Scroll/Details")
	if not await wait_until(func():return details.visible and screen._operation.is_empty()):fail("inspect friend profile");return
	if details.get_node("Identity/Text/Name").text!=OS.get_environment("QA_OTHER"):fail("inspected identity");return
	if not details.get_node("Identity/Text/Presence").text=="Online":fail("inspected presence");return
	if details.get_node("Identity/Portrait").texture==null or details.get_node("Progress").max_value!=15:fail("inspected portrait and progress");return
	if screen._layout.get_node("Profile").visible or screen._layout.get_node("Scroll").visible:fail("friend profile read only layout");return
	screen._layout.get_node("FriendProfile/Toolbar/Back").pressed.emit()
	if screen._layout.get_node("FriendProfile").visible or not screen._layout.get_node("Scroll").visible:fail("return from inspected profile");return
	print("PASS friend profile inspection, read-only view and return")
	if not await wait_until(func():return screen._operation.is_empty()):fail("rankings busy");return
	screen._layout.get_node("Rankings").pressed.emit()
	var ranks=screen._layout.get_node("Leaderboard/Scroll/Rows")
	if not await wait_until(func():return ranks.get_child_count()==2 and screen._operation.is_empty()):fail("rankings load");return
	if not screen._layout.get_node("Leaderboard").visible or screen._layout.get_node("Scroll").visible:fail("rankings layout");return
	if not screen._layout.get_node("Leaderboard/Summary").text.contains("Your rank: #1"):fail("rank tie");return
	var category:OptionButton=screen._layout.get_node("Leaderboard/Controls/Category")
	for index in [1,2]:
		category.select(index)
		category.item_selected.emit(index)
		if not await wait_until(func():return ranks.get_child_count()==2 and screen._operation.is_empty()):fail("ranking category");return
	var period:OptionButton=screen._layout.get_node("Leaderboard/Controls/Period")
	period.select(1)
	period.item_selected.emit(1)
	if not await wait_until(func():return screen._operation.is_empty() and not screen._season_key.is_empty()):fail("monthly ranking season");return
	if not screen._layout.get_node("Leaderboard/Season").visible or screen._season_deadline<=Time.get_ticks_msec():fail("monthly ranking countdown");return
	for index in [0,1,2]:
		category.select(index)
		category.item_selected.emit(index)
		if not await wait_until(func():return ranks.get_child_count()==2 and screen._operation.is_empty()):fail("monthly ranking category");return
	print("PASS all monthly categories and server countdown")
	screen._layout.get_node("Leaderboard/Challenges").pressed.emit()
	var challenges=screen._layout.get_node("SeasonChallenges")
	var challenge_rows=challenges.get_node("Scroll/Rows")
	if not await wait_until(func():return challenges.visible and screen._operation.is_empty() and challenge_rows.get_child_count()==5):fail("season challenge load");return
	if not challenges.get_node("Timing").text.contains("(UTC)"):fail("challenge countdown");return
	if OS.get_environment("QA_SEASON_FIXTURE")=="1":
		var claim_button:Button=challenge_rows.get_child(0).get_node("Row/Reward/Claim")
		if claim_button.disabled or not challenge_rows.get_child(1).get_node("Row/Reward/Claim").disabled:fail("season challenge eligibility");return
		var batch_button:Button=challenges.get_node("Toolbar/ClaimAll")
		if batch_button.disabled:fail("challenge claim all eligibility");return
		batch_button.pressed.emit()
		if not await wait_until(func():return screen._operation.is_empty() and challenge_rows.get_child_count()==5 and challenge_rows.get_child(0).get_node("Row/Reward/Claim").text=="Claimed"):fail("challenge claim");return
		if AuthGateway.online_season_challenge_claimable!=0:fail("challenge count");return
	challenges.get_node("Toolbar/Back").pressed.emit()
	if not await wait_until(func():return ranks.get_child_count()==2 and screen._operation.is_empty()):fail("challenge back");return
	print("PASS season challenge panel, countdown, server eligibility and navigation")

	screen._layout.get_node("Leaderboard/Toolbar/Results").pressed.emit()
	var results=screen._layout.get_node("SeasonResults/Scroll/Rows")
	if not await wait_until(func():return results.get_child_count()>0 and screen._operation.is_empty()):fail("season results load");return
	if not screen._layout.get_node("SeasonResults").visible or screen._layout.get_node("Leaderboard").visible:fail("season results navigation");return
	if not screen._layout.get_node("SeasonResults/Rules").text.contains("2026-12"):fail("season rules");return
	if OS.get_environment("QA_SEASON_FIXTURE")=="1":
		AuthGateway.refresh_social_summary()
		if not await wait_until(func():return AuthGateway.online_season_claimable==1 and AuthGateway._season_announced.has("2002-01-01:combat")):fail("season reward notification");return
		var observer_calls:Array=[]
		var observe=func(count:int):observer_calls.append(count)
		AuthGateway.season_rewards_ready.connect(observe)
		AuthGateway._announce_season_ready([{"id":"2002-01-01:combat"}])
		AuthGateway.season_rewards_ready.disconnect(observe)
		if not observer_calls.is_empty():fail("duplicate season notification");return
		var history_toggle:CheckButton=screen._layout.get_node("SeasonResults/History")
		history_toggle.button_pressed=true
		if not await wait_until(func():return results.get_child_count()==1 and results.get_child(0).get_node("Row/Info").text.contains("Arena Sovereign")):fail("championship history");return
		if results.get_child(0).get_node("Row/Claim").visible:fail("history read only");return
		history_toggle.button_pressed=false
		var claim_button:Button=results.get_child(0).get_node("Row/Claim")
		if claim_button.disabled:fail("season claim button disabled");return
		claim_button.pressed.emit()
		if not await wait_until(func():return screen._operation.is_empty() and results.get_child_count()==1 and results.get_child(0).get_node("Row/Claim").text=="Claimed"):fail("season claim persisted");return
		if AuthGateway.online_season_claimable!=0:fail("season reward badge clear");return
		print("PASS actual reward notification, deduplication, championship history and one-time UI claim")
	screen._layout.get_node("SeasonResults/Toolbar/Back").pressed.emit()
	if not await wait_until(func():return ranks.get_child_count()==2 and screen._operation.is_empty()):fail("season results back");return
	print("PASS season results view and navigation")

	var scope:OptionButton=screen._layout.get_node("Leaderboard/Controls/Scope")
	scope.select(1)
	scope.item_selected.emit(1)
	if not await wait_until(func():return screen._operation.is_empty() and screen._layout.get_node("Leaderboard/Summary").text.begins_with("Unranked")):fail("global opt-in default");return
	var visibility:CheckButton=screen._layout.get_node("Leaderboard/Visibility")
	visibility.button_pressed=true
	if not await wait_until(func():return screen._operation.is_empty() and screen._ranking_enabled and screen._layout.get_node("Leaderboard/Summary").text.begins_with("Your rank:")):fail("global opt-in");return
	if OS.get_environment("QA_SEASON_FIXTURE")=="1":
		screen._layout.get_node("Leaderboard/Toolbar/Hall").pressed.emit()
		var hall=screen._layout.get_node("ChampionshipHall")
		var hall_rows=hall.get_node("Scroll/Rows")
		if not await wait_until(func():return hall.visible and screen._operation.is_empty() and hall_rows.get_child_count()>0):fail("hall load");return
		if not hall.get_node("Summary").text.contains("2002-01"):fail("hall season");return
		if not hall_rows.get_children().any(func(r):return r.get_node("Row/Name").text.contains(" (You)") and r.get_node("Row/Name").text.contains("Arena Sovereign")):fail("hall self champion");return
		var hall_categories:OptionButton=hall.get_node("Filters/Category")
		hall_categories.select(1)
		hall_categories.item_selected.emit(1)
		if not await wait_until(func():return screen._operation.is_empty() and hall.get_node("Summary").text.contains("No visible champions")):fail("hall filter");return
		hall.get_node("Toolbar/Back").pressed.emit()
		if not await wait_until(func():return screen._operation.is_empty() and screen._layout.get_node("Leaderboard").visible):fail("hall return");return
		print("PASS actual championship hall, frozen champion, category filter and back navigation")
	visibility.button_pressed=false
	if not await wait_until(func():return screen._operation.is_empty() and not screen._ranking_enabled and screen._layout.get_node("Leaderboard/Summary").text.begins_with("Unranked")):fail("global opt-out");return
	print("PASS global ranking scope, opt-in personal rank and opt-out")
	period.select(0)
	period.item_selected.emit(0)
	if not await wait_until(func():return screen._operation.is_empty() and not screen._layout.get_node("Leaderboard/Season").visible):fail("lifetime ranking return");return

	screen._layout.get_node("Leaderboard/Toolbar/Back").pressed.emit()
	if screen._layout.get_node("Leaderboard").visible or not screen._layout.get_node("Scroll").visible:fail("ranking return");return
	if OS.get_environment("QA_SEASON_FIXTURE")=="1":
		if not await wait_until(func():return screen._operation.is_empty() and screen._title_catalog.has("season_combat_champion")):fail("claimed title refresh");return
		var title_options:OptionButton=screen._layout.get_node("Titles/Options")
		for i in range(title_options.item_count):
			if title_options.get_item_metadata(i)=="season_combat_champion":
				if title_options.is_item_disabled(i):fail("season title locked after claim");return
				title_options.select(i)
				title_options.item_selected.emit(i)
		screen._layout.get_node("Titles/Equip").pressed.emit()
		if not await wait_until(func():return screen._operation.is_empty() and screen._equipped_title=="season_combat_champion"):fail("season title equip");return
		print("PASS season title selectable and equipped after reward claim")
	print("PASS all three friend leaderboards, tied ranks and back navigation")

	var expected_id:=str(screen._friends[0].id)
	var friend_row=screen._layout.get_node("Scroll/Rows").get_child(0)
	if role=="A":
		if CoopGateway.create_lobby("six_zone_willow_fields",4)!=OK:fail("create party");return
		var created=await CoopGateway.lobby_result
		if not created[1]:fail("create party response");return
		if not await wait_until(func():return screen._operation.is_empty()):fail("invite busy");return
		for button in screen._layout.get_node("Scroll/Rows").get_child(0).get_children():
			if button is Button and button.text=="Invite":button.pressed.emit()
		if not await wait_until(func():return screen._operation.is_empty() and str(screen._layout.get_node("Status").text).begins_with("Party invitation sent")):fail("send invitation");return
	else:
		if not await wait_until(func():return screen._party_invites.size()==1 and screen._operation.is_empty(),18.0):fail("receive invitation");return
		var invite_row=screen._layout.get_node("Scroll/Rows").get_child(1)
		for button in invite_row.get_children():
			if button is Button and button.text=="Accept":button.pressed.emit()
		if not await wait_until(func():return screen._operation.is_empty() and str(screen._layout.get_node("Status").text).begins_with("Joined party")):fail("accept invitation");return
		if CoopGateway.fetch_current_lobby()!=OK:fail("fetch joined party");return
		var current=await CoopGateway.lobby_result
		if not current[1] or current[2].get("lobby",{}).get("members",[]).size()!=2:fail("party membership");return
	print("PASS direct party invitation UI")
	if not await wait_until(func():return screen._operation.is_empty()):fail("message busy");return
	friend_row=screen._layout.get_node("Scroll/Rows").get_child(0)
	var message_button: Button
	for button in friend_row.get_children():
		if button is Button and button.text=="Message":message_button=button
	if message_button==null:fail("missing message button");return
	message_button.pressed.emit()
	await get_tree().process_frame
	var chat=zone.get_node("OverlayRouter").active_overlay
	if chat==null or chat==screen or zone.checkpoint_player.input_enabled:fail("direct chat transition");return
	if not await wait_until(func():return chat._contacts_loaded and chat._operation.is_empty()):fail("direct contacts");return
	if chat._channel!="private" or chat._recipient!=expected_id:fail("incorrect direct recipient");return
	var field=chat._layout.get_node("Composer/Message")
	field.text="Direct "+role
	chat._layout.get_node("Composer/Send").pressed.emit()
	if not await wait_until(func():return field.text.is_empty() and chat._last_messages.size()==2,18.0):fail("direct messages");return
	print("PASS direct friend messaging and continuous world input lock")
	chat.close_screen()
	await get_tree().process_frame
	if not zone.checkpoint_player.input_enabled:fail("movement restore");return
	var title=load("res://scenes/ui/main_menu.tscn").instantiate()
	add_child(title)
	await get_tree().process_frame
	title._open_profile()
	var title_social=title.get_node("PlayerProfileOverlay")
	if not await wait_until(func():return title_social._friends.size()==1 and title_social._operation.is_empty()):fail("title friends");return
	var title_row=title_social._layout.get_node("Scroll/Rows").get_child(0)
	for button in title_row.get_children():
		if button is Button and button.text=="Message":button.pressed.emit()
	await get_tree().process_frame
	var title_chat=title.get_node("PlayerProfileOverlay")
	if not await wait_until(func():return title_chat._contacts_loaded and title_chat._operation.is_empty()):fail("title chat contacts");return
	if title_chat._channel!="private" or title_chat._recipient!=expected_id:fail("title direct recipient");return
	title_chat.close_screen()
	await get_tree().process_frame
	if title.has_node("PlayerProfileOverlay"):fail("title chat close");return
	title.queue_free()
	print("PASS main-menu profile direct chat and close")
	zone.queue_free()
	for i in range(3):await get_tree().process_frame
	AudioDirector.stop_all_audio_immediately()
	await get_tree().create_timer(0.35).timeout
	get_tree().quit(0)
