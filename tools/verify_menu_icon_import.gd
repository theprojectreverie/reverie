extends SceneTree

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var scene := load("res://scenes/ui/main_menu.tscn") as PackedScene
	if scene == null:
		push_error("MENU ICON QA FAIL: main menu scene missing")
		quit(1)
		return
	var menu := scene.instantiate() as MainMenu
	root.add_child(menu)
	await process_frame
	var game_state: Node = root.get_node("GameState")
	var inventory_domain: Node = game_state.get("inventory_domain")
	var mapping := {
		"ReferenceInterface/CurrencyBar/PremiumCurrency": "crystals_double",
		"ReferenceInterface/CurrencyBar/GoldCurrency": "gold_coins",
		"ReferenceInterface/CurrencyBar/PaidCurrency": "paid_moonstone",
		"ReferenceInterface/MailButton": "mail_stationery",
		"ReferenceInterface/SettingsShortcut": "settings_gear",
		"ReferenceInterface/LeftRail/EventsButton": "events_calendar",
		"ReferenceInterface/LeftRail/CalendarButton": "calendar_grid",
		"ReferenceInterface/LeftRail/GiftsButton": "gifts_box",
		"ReferenceInterface/LeftRail/AchievementsButton": "achievements_crown",
		"ReferenceInterface/BottomNavigation/WorldButton": "world_compass",
		"ReferenceInterface/BottomNavigation/CommunicationButton": "messages_envelope",
		"ReferenceInterface/BottomNavigation/CharactersButton": "party",
		"ReferenceInterface/BottomNavigation/InventoryButton": "inventory_chest",
		"ReferenceInterface/BottomNavigation/SummonButton": "crystals_single",
		"ReferenceInterface/BottomNavigation/StoryButton": "story_book",
		"ReferenceInterface/BottomNavigation/CombatButton": "combat_swords",
		"ReferenceInterface/BottomNavigation/CastleButton": "castle_moon",
		"ReferenceInterface/BottomNavigation/ResourcesButton": "resources_crystals"
	}
	var failures: Array[String] = []
	for node_path in mapping:
		var button := menu.get_node_or_null(node_path) as Button
		if button == null:
			failures.append("missing button " + node_path)
			continue
		if button.icon == null:
			failures.append("missing icon on " + node_path)
			continue
		var is_crystals: bool = node_path.ends_with("/PremiumCurrency")
		var is_gold: bool = node_path.ends_with("/GoldCurrency")
		var is_paid: bool = node_path.ends_with("/PaidCurrency")
		if is_crystals:
			var expected_crystals := UIFactory.number(int(inventory_domain.call("currency", "crystals")))
			if button.text != expected_crystals:
				failures.append("crystal balance mismatch: " + button.text + " expected " + expected_crystals)
		elif is_gold:
			var expected_gold := UIFactory.number(int(inventory_domain.call("currency", "gold")))
			if button.text != expected_gold:
				failures.append("gold balance mismatch: " + button.text + " expected " + expected_gold)
		elif is_paid:
			var expected_paid := UIFactory.number(int(inventory_domain.call("currency", "paid_moonstones")))
			if button.text != expected_paid:
				failures.append("paid moonstone balance mismatch: " + button.text + " expected " + expected_paid)
		elif not button.text.is_empty():
			failures.append("caption still visible on " + node_path + ": " + button.text)
		if button.vertical_icon_alignment != VERTICAL_ALIGNMENT_CENTER:
			failures.append("icon is not vertically centered on " + node_path)
		var expected := "res://assets/ui/buttons/%s.png" % mapping[node_path]
		if button.icon.resource_path != expected:
			failures.append("wrong icon on %s: %s" % [node_path, button.icon.resource_path])
		var icon_image := button.icon.get_image()
		var expected_size := Vector2i(256, 256)
		if icon_image == null or icon_image.is_empty() or icon_image.get_size() != expected_size:
			failures.append("invalid image dimensions/data on " + node_path)
	# Verify the displayed balances react immediately to wallet changes.
	inventory_domain.call("add_currency", "crystals", 7)
	inventory_domain.call("add_currency", "gold", 13)
	inventory_domain.call("add_currency", "paid_moonstones", 5)
	var crystal_button := menu.get_node("ReferenceInterface/CurrencyBar/PremiumCurrency") as Button
	var gold_button := menu.get_node("ReferenceInterface/CurrencyBar/GoldCurrency") as Button
	var paid_button := menu.get_node("ReferenceInterface/CurrencyBar/PaidCurrency") as Button
	if crystal_button.text != UIFactory.number(int(inventory_domain.call("currency", "crystals"))):
		failures.append("crystal balance did not refresh after currency_changed")
	if gold_button.text != UIFactory.number(int(inventory_domain.call("currency", "gold"))):
		failures.append("gold balance did not refresh after currency_changed")
	if paid_button.text != UIFactory.number(int(inventory_domain.call("currency", "paid_moonstones"))):
		failures.append("paid moonstone balance did not refresh after currency_changed")
	# Restore the exact balances after the live-update test.
	inventory_domain.call("spend_currency", "crystals", 7)
	inventory_domain.call("spend_currency", "gold", 13)
	inventory_domain.call("spend_currency", "paid_moonstones", 5)
	if failures.is_empty():
		print("MENU ICON QA PASS: all %d menu controls use intended textures, icon-only captions are preserved, and crystal, gold, and paid moonstone balances refresh on wallet changes." % mapping.size())
		quit(0)
	else:
		for failure in failures:
			push_error(failure)
		push_error("MENU ICON QA FAIL: %d issue(s)." % failures.size())
		quit(2)
