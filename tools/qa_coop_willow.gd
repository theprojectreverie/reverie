extends Node
func _ready() -> void:
	call_deferred("run")
func fail(reason: String) -> void:
	print("FAIL ",reason)
	get_tree().quit(1)
func run() -> void:
	AuthGateway.api_base_url = OS.get_environment("QA_API")
	MultiplayerGateway.websocket_url = OS.get_environment("QA_WS")
	if AuthGateway.login(OS.get_environment("QA_NAME"), OS.get_environment("QA_PASSWORD")) != OK:
		fail("login start")
		return
	var result: Array = await AuthGateway.auth_result
	if not bool(result[1]):
		fail("login rejected")
		return
	GameState.quest_domain.flags["tutorial_complete"] = true
	MultiplayerGateway.standalone_expedition_id = OS.get_environment("QA_LOBBY")
	MultiplayerGateway.standalone_expedition_region = "six_zone_willow_fields"
	var zone = load("res://scenes/world/six_zone_reverie/individual_zones/zone_03_willow_fields_standalone.tscn").instantiate()
	add_child(zone)
	var sync = zone.get_node("CoopWorldSync")
	var deadline := Time.get_ticks_msec()+10000
	while not sync._snapshot_ready or sync.remote_players.size()!=1:
		if Time.get_ticks_msec()>deadline:
			fail("snapshot")
			return
		await get_tree().process_frame
	var monster = zone.get_node_or_null("SharedWillowSlime")
	if monster == null or monster.world_hp != 100.0:
		fail("authored patrol missing")
		return
	print("PASS authored Willow Slime present; 100 HP")
	var remote:RemotePlayerAvatar=sync.remote_players.values()[0]
	if remote.title_label.visible:fail("empty title label");return
	# Exercise the actual nameplate update path without fabricating a server reward.
	sync._ensure_remote(remote.player_id,remote.display_name,remote.position,"Dawn Wanderer")
	if not remote.title_label.visible or remote.title_label.text!="Dawn Wanderer":fail("nameplate update");return
	sync._ensure_remote(remote.player_id,"Wanderer",remote.position)
	if remote.title_label.text!="Dawn Wanderer":fail("position erased title");return
	sync._ensure_remote(remote.player_id,remote.display_name,remote.position,"")
	if remote.title_label.visible:fail("title clear");return
	print("PASS nameplate display, movement preservation and unequip")

	await get_tree().physics_frame
	var query := PhysicsPointQueryParameters2D.new()
	query.position=monster.global_position
	query.collision_mask=1
	if not zone.get_world_2d().direct_space_state.intersect_point(query,1).is_empty():
		fail("monster spawn blocked")
		return
	var local_gold := GameState.currency("gold")
	var local_quest := GameState.quest_domain.quest_state("royal_gate_patrol")
	var role := OS.get_environment("QA_ROLE")
	await get_tree().create_timer(1.0 if role=="A" else 1.3).timeout
	deadline=Time.get_ticks_msec()+10000
	while not monster.defeated:
		monster.receive_world_hit(25.0)
		await get_tree().create_timer(0.68).timeout
		if Time.get_ticks_msec()>deadline:
			fail("patrol defeat")
			return
	if monster.world_hp!=0.0 or monster.coop_motion_samples<1:
		fail("shared defeat or motion missing")
		return
	print("PASS shared Willow Slime defeat and server motion")
	deadline=Time.get_ticks_msec()+5000
	while int(AuthGateway.online_wallet.get("gold",0))!=15 or int(AuthGateway.online_inventory.get("glade_sap",0))!=1:
		if Time.get_ticks_msec()>deadline:
			fail("wallet")
			return
		await get_tree().process_frame
	if GameState.currency("gold") != local_gold or GameState.quest_domain.quest_state("royal_gate_patrol") != local_quest:
		fail("offline progress changed")
		return
	print("PASS online rewards, offline quest and currency isolated")
	var daily=load("res://scenes/ui/daily_quests_screen.tscn").instantiate()
	add_child(daily)
	deadline=Time.get_ticks_msec()+10000
	while daily._remote.is_empty() or not daily._operation.is_empty():
		if Time.get_ticks_msec()>deadline:fail("online quest load");return
		await get_tree().process_frame
	if not daily._online or daily._remote.rows[1].progress!=1 or daily._remote.rows[2].progress!=1:
		fail("shared quest contribution");return
	var all_button:Button=daily._layout.get_node("Actions/ClaimAll")
	if all_button.disabled:fail("claim all disabled");return
	if not daily._layout.get_node("Scroll/Rows/Activity1").visible or daily._remote.rows[4].can_claim:fail("activity initial state");return
	all_button.pressed.emit()
	while daily._remote.is_empty() or not daily._remote.rows[0].claimed or not daily._remote.rows[2].claimed or int(AuthGateway.online_wallet.get("gold",0))!=515:
		if Time.get_ticks_msec()>deadline:fail("batch claim or wallet refresh");return
		await get_tree().process_frame
	if not all_button.disabled:fail("empty batch remains enabled");return
	if not daily._remote.rows[4].claimed or daily._remote.rows[5].can_claim:fail("milestone threshold");return
	daily._layout.get_node("Actions/History").pressed.emit()
	while not daily._history_loaded:
		if Time.get_ticks_msec()>deadline:fail("history load");return
		await get_tree().process_frame
	if daily._history.size()!=3 or not daily._layout.get_node("HistoryScroll").visible:fail("history rows");return
	if not daily._layout.get_node("HistoryScroll/Entries").text.contains("Activity - Daily Momentum"):fail("history amounts");return
	daily._layout.get_node("Actions/History").pressed.emit()
	while not daily._operation.is_empty():
		if Time.get_ticks_msec()>deadline:fail("history return");return
		await get_tree().process_frame
	print("PASS Claim All UI and ledger-backed reward history")
	if GameState.currency("gold")!=local_gold:fail("online claim changed story wallet");return
	print("PASS online daily journal and claims, shared victory progress, server wallet isolation")
	daily._layout.get_node("Modes/Weekly").pressed.emit()
	deadline=Time.get_ticks_msec()+10000
	while daily._remote.is_empty() or not daily._operation.is_empty():
		if Time.get_ticks_msec()>deadline:fail("weekly journal");return
		await get_tree().process_frame
	if not daily._weekly or daily._remote.rows[0].progress!=1 or daily._remote.rows[1].progress!=1 or daily._remote.rows[2].progress!=1:
		fail("weekly quest aggregation");return
	if daily._layout.get_node("Scroll/Rows/Activity1").visible:fail("activity leaked to weekly");return
	if daily._seconds_remaining()<=0 or daily._seconds_remaining()>604800:fail("weekly countdown");return
	if not daily._layout.get_node("Reset").text.begins_with("Weekly reset"):fail("weekly countdown label");return
	daily._layout.get_node("Modes/Online").pressed.emit()
	while daily._remote.is_empty() or not daily._operation.is_empty():
		if Time.get_ticks_msec()>deadline:fail("daily journal return");return
		await get_tree().process_frame
	if daily._weekly or not daily._remote.rows[0].claimed or daily._seconds_remaining()>86400:fail("daily tab isolation");return
	print("PASS weekly journal, real combat credit, daily tab isolation and reset countdown")
	daily._layout.get_node("Modes/Monthly").pressed.emit()
	deadline=Time.get_ticks_msec()+10000
	while daily._remote.is_empty() or not daily._operation.is_empty():
		if Time.get_ticks_msec()>deadline:fail("monthly journal");return
		await get_tree().process_frame
	if not daily._monthly or daily._weekly or daily._remote.rows[0].progress!=1 or daily._remote.rows[1].progress!=1 or daily._remote.rows[2].progress!=1:
		fail("monthly aggregation or tab isolation");return
	if daily._remote.rows[0].claimed or daily._layout.get_node("Scroll/Rows/Activity1").visible:fail("monthly claim isolation");return
	if daily._seconds_remaining()<=0 or daily._seconds_remaining()>2678400:fail("monthly countdown");return
	if not daily._layout.get_node("Reset").text.begins_with("Monthly reset"):fail("monthly countdown label");return
	print("PASS monthly journal, real daily credits, independent claims and calendar reset")
	daily._layout.get_node("Modes/Achievements").pressed.emit()
	deadline=Time.get_ticks_msec()+10000
	while daily._remote.is_empty() or not daily._operation.is_empty():
		if Time.get_ticks_msec()>deadline:fail("achievement journal");return
		await get_tree().process_frame
	if not daily._achievements or daily._remote.rows[0].progress!=1 or daily._remote.rows[1].progress!=1:
		fail("achievement lifetime progress");return
	if daily._remote.rows[0].claimed or not daily._remote.rows[0].can_claim:fail("first duty state");return
	if not AuthGateway._achievement_announced.has("first_duty"):fail("achievement ready notification");return
	var notification_counts:Array=[]
	var observer=func(count:int):notification_counts.append(count)
	AuthGateway.achievement_rewards_ready.connect(observer)
	AuthGateway._announce_achievement_ready([{"id":"first_duty","title":"First Steps"}])
	AuthGateway._announce_achievement_ready([])
	AuthGateway._announce_achievement_ready([{"id":"first_duty","title":"First Steps"}])
	AuthGateway.achievement_rewards_ready.disconnect(observer)
	if not notification_counts.is_empty():fail("duplicate achievement notification");return
	if not daily._layout.get_node("Scroll/Rows/Blessing/Row/Info/Description").text.contains("Rare"):fail("achievement title tier");return
	print("PASS achievement ready notification and duplicate suppression")

	daily._layout.get_node("Actions/ClaimAll").pressed.emit()
	while not daily._operation.is_empty() or not daily._remote.rows[0].claimed or int(AuthGateway.online_wallet.get("gold",0))!=715:
		if Time.get_ticks_msec()>deadline:fail("achievement claim");return
		await get_tree().process_frame
	if not daily._layout.get_node("Reset").text.contains("Never reset"):fail("achievement reset label");return
	print("PASS permanent achievement UI, first duty payout and combat progress")
	var category:OptionButton=daily._layout.get_node("Category")
	category.select(5)
	category.item_selected.emit(5)
	if not daily._layout.get_node("Scroll/Rows/Landmarks").visible or daily._layout.get_node("Scroll/Rows/Blessing").visible:
		fail("exploration category filter");return
	category.select(6)
	category.item_selected.emit(6)
	if not daily._layout.get_node("Scroll/Rows/MythicCollection").visible or daily._layout.get_node("Scroll/Rows/Landmarks").visible:
		fail("collection category filter");return
	category.select(7)
	category.item_selected.emit(7)
	if not daily._layout.get_node("Scroll/Rows/MythicAscension").visible or daily._layout.get_node("Scroll/Rows/SiblingBond").visible:fail("ascension filter");return
	category.select(8)
	category.item_selected.emit(8)
	if not daily._layout.get_node("Scroll/Rows/SiblingBond").visible or daily._layout.get_node("Scroll/Rows/MythicAscension").visible:fail("bond filter");return
	category.select(0)
	category.item_selected.emit(0)
	print("PASS expanded achievement categories and all fifteen rows")

	daily.close_screen()
	var social=load("res://scenes/ui/social_screen.tscn").instantiate()
	add_child(social)
	deadline=Time.get_ticks_msec()+10000
	while not social._profile_loaded or not social._operation.is_empty():
		if Time.get_ticks_msec()>deadline:fail("profile title load");return
		await get_tree().process_frame
	var titles:OptionButton=social._layout.get_node("Titles/Options")
	if titles.item_count!=16 or titles.is_item_disabled(1) or not titles.is_item_disabled(2):fail("title unlock state");return
	titles.select(1)
	titles.item_selected.emit(1)
	if social._layout.get_node("Titles/Equip").disabled:fail("title equip disabled");return
	social._layout.get_node("Titles/Equip").pressed.emit()
	while social._equipped_title!="first_duty" or not social._operation.is_empty():
		if Time.get_ticks_msec()>deadline:fail("title equip");return
		await get_tree().process_frame
	if not social._layout.get_node("Titles/Showcase").text.contains("Dawn Wanderer"):fail("title showcase");return
	var showcase_progress:ProgressBar=social._layout.get_node("AchievementShowcase/Progress")
	var showcase_preview:Label=social._layout.get_node("AchievementShowcase/Preview")
	if showcase_progress.value!=1 or showcase_progress.max_value!=15:fail("showcase progress");return
	if showcase_preview.text!="Rare | Dawn Wanderer":fail("title rarity preview");return
	print("PASS title selector, achievement ownership, equip and showcase")
	social._layout.get_node("AchievementShowcase/Open").pressed.emit()
	if not social._layout.get_node("BadgeGallery").visible or social._layout.get_node("Scroll").visible:fail("badge gallery navigation");return
	var badge_rows=social._layout.get_node("BadgeGallery/Scroll/Rows")
	if badge_rows.get_child_count()!=15:fail("badge catalog");return
	if not badge_rows.get_child(1).get_node("Row/Pin").disabled:fail("locked badge enabled");return
	badge_rows.get_child(0).get_node("Row/Pin").button_pressed=true
	if social._draft_pins!=["first_duty"]:fail("badge selection");return
	social._layout.get_node("BadgeGallery/Toolbar/Save").pressed.emit()
	deadline=Time.get_ticks_msec()+10000
	while social._saved_pins!=["first_duty"] or not social._operation.is_empty():
		if Time.get_ticks_msec()>deadline:fail("badge save");return
		await get_tree().process_frame
	if not social._layout.get_node("BadgeGallery/Stats").text.contains("1 expedition victories"):fail("server profile stats");return
	social._layout.get_node("BadgeGallery/Toolbar/Done").pressed.emit()
	if not social._layout.get_node("Titles/Showcase").text.contains("Pinned: Dawn Wanderer"):fail("pinned profile showcase");return
	print("PASS profile badge gallery, earned-only pin, persistence and verified statistics")

	# Both real clients equip their title above. Request existing heartbeat
	# refresh until the peer's committed title arrives, without reconnecting.
	deadline=Time.get_ticks_msec()+10000
	while remote.display_title!="Dawn Wanderer":
		MultiplayerGateway.ping_server()
		await get_tree().create_timer(0.5).timeout
		if Time.get_ticks_msec()>deadline:fail("live peer title refresh");return
	if not remote.title_label.visible or remote.title_label.text!="Dawn Wanderer":fail("live nameplate");return
	if remote.title_label.get_theme_color("font_color")!=Color("#8fc9ec"):fail("live title rarity color");return
	print("PASS live server-confirmed peer title on existing nameplate")

	social.close_screen()

	MultiplayerGateway.disconnect_from_lobby()
	zone.queue_free()
	for i in range(3):
		await get_tree().process_frame
	AudioDirector.stop_all_audio_immediately()
	await get_tree().create_timer(0.35).timeout
	get_tree().quit(0)
