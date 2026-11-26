class_name MainMenu
extends Control
## Composition root. Presentation, routing and overlay ownership live in child nodes.

signal play_requested
signal quit_requested

@onready var navigation: MainMenuNavigationComponent = $Navigation
@onready var skin: MainMenuSkinComponent = $Skin
@onready var overlays: MainMenuOverlayComponent = $Overlays
@onready var ravienna_line: Label = $RaviennaDialogue/DialogueMargin/DialogueContent/RaviennaLine

var ravienna_lines: Array[String] = [
	"The night is young. Shall we see what secrets it keeps?",
	"Careful, darling. Not every shadow is as harmless as it looks.",
	"I was beginning to think you had forgotten me.",
	"Come closer. I have a little story for you.",
	"The roses are beautiful tonight… almost as beautiful as the danger.",
	"Stay a while. The world can wait for us.",
	"Do you hear that? The castle is whispering again.",
	"I wonder what fate has written for us this time."
]
# Newly authored ambient lines, kept separate from story dialogue and quests.
const MENU_DIALOGUE := {
 "kael": ["Ready when you are. The road won't wait forever.","Keep your blade sharp and your eyes open.","We've come a long way. There's still more ahead."],
 "mirene": ["Pick a card, darling. Or shall I pick your fate?","Every good trick starts with a smile.","The stage is ours. What shall we play today?"],
 "crimson_witch": ["Even in shadow, a lily can bloom.","Rest a while. The dusk gardens are quiet tonight.","Patience is a spell of its own."],
 "elathra": ["Welcome back. What shall we discover today?","One step at a time. I'll guide you if you need me.","There is always something new to learn."]
}
var ravienna_line_index := 0
var _menu_dialogue_key := "ravienna"
var _dialogue_requested := false
var _displayed_profile_avatar := ""
var _notification_elapsed := 0.0

func _ready() -> void:
	UIFactory.set_full_rect(self)
	theme = UITheme.build()
	_fit_ravienna_dialogue()
	navigation.bind(self)
	skin.bind(self)
	$MenuCharacterSelector.character_changed.connect(_on_menu_character_changed)
	$MenuCharacterSelector.gallery_visibility_changed.connect(_on_menu_gallery_visibility)
	$MenuDialogueButton.pressed.connect(_toggle_menu_dialogue)
	$RaviennaDialogue.resized.connect(_fit_ravienna_dialogue)
	_on_menu_character_changed($MenuCharacterSelector._displayed)
	var friends := $ReferenceInterface/LeftRail/FriendsButton as Button
	friends.pressed.connect(_open_profile)
	var calendar := $ReferenceInterface/LeftRail/CalendarButton as Button
	calendar.tooltip_text = "Daily rewards"
	var chat := $ReferenceInterface/BottomNavigation/CommunicationButton as Button
	chat.tooltip_text = "Chat - world, party and private"
	var daily_quests := $ReferenceInterface/LeftRail/EventsButton as Button
	daily_quests.text="QUESTS"
	daily_quests.tooltip_text="Daily quests"
	daily_quests.vertical_icon_alignment=VERTICAL_ALIGNMENT_TOP
	daily_quests.add_theme_font_size_override("font_size",12)
	daily_quests.add_theme_constant_override("icon_max_width",44)
	for button in [calendar,chat]:
		button.text = "DAILY" if button==calendar else "CHAT"
		button.vertical_icon_alignment=VERTICAL_ALIGNMENT_TOP
		button.add_theme_font_size_override("font_size",12)
		button.add_theme_constant_override("icon_max_width",44 if button==calendar else 48)
	var bottom := $ReferenceInterface/BottomNavigation
	var labels := {"WorldButton": "MAP", "CharactersButton": "PARTY", "InventoryButton": "BAG", "SummonButton": "SUMMON", "StoryButton": "PLAY", "PvpButton": "PVP"}
	for node_name in labels:
		var button := bottom.get_node(node_name) as Button
		button.text = labels[node_name]
		button.tooltip_text = labels[node_name]
		if button.icon != null:
			button.vertical_icon_alignment = VERTICAL_ALIGNMENT_TOP
			button.add_theme_font_size_override("font_size", 13)
			button.add_theme_constant_override("icon_max_width", 54)
	AuthGateway.social_summary_changed.connect(_on_friend_notification)
	AuthGateway.unread_messages_changed.connect(_on_chat_notification)
	_refresh_menu_notifications()
	AuthGateway.refresh_social_summary()
	AuthGateway.profile_picture_changed.connect(func(_avatar: String): _refresh_profile_avatar())
	AuthGateway.online_wallet_changed.connect(_refresh_currency_counts)
	AuthGateway.authentication_changed.connect(_on_profile_identity_changed)
	AuthGateway.refresh_online_wallet()
	_refresh_profile_progress()
	_refresh_currency_counts()
	for currency in $ReferenceInterface/CurrencyBar.get_children():
		if currency is Button:
			if currency.name == "PaidCurrency" and OS.get_name() not in ["Android","iOS","Web"]:
				currency.mouse_filter = Control.MOUSE_FILTER_STOP
				currency.focus_mode = Control.FOCUS_ALL
				currency.pressed.connect(_show_paid_currency)
			else:
				currency.mouse_filter = Control.MOUSE_FILTER_IGNORE
				currency.focus_mode = Control.FOCUS_NONE
	var profile_hit_target := get_node_or_null("ReferenceInterface/TopProfile/ProfileHitTarget") as Button
	if profile_hit_target != null:
		profile_hit_target.add_theme_stylebox_override("normal", StyleBoxEmpty.new())
		profile_hit_target.add_theme_stylebox_override("hover", StyleBoxEmpty.new())
		profile_hit_target.add_theme_stylebox_override("pressed", StyleBoxEmpty.new())
		profile_hit_target.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
		profile_hit_target.pressed.connect(_open_profile)
		profile_hit_target.tooltip_text = "Player profile and account"
	var event_bus := get_node_or_null("/root/EventBus")
	if event_bus != null and not event_bus.is_connected("currency_changed", _refresh_currency_counts):
		event_bus.connect("currency_changed", _refresh_currency_counts)
	overlays.bind(self)
	navigation.play_requested.connect(play_requested.emit)
	navigation.world_requested.connect(overlays.open_world_map)
	navigation.summon_requested.connect(overlays.open_summon)
	navigation.inventory_requested.connect(overlays.open_inventory)
	navigation.settings_requested.connect(overlays.open_settings)
	navigation.characters_requested.connect(overlays.open_characters)
	navigation.events_requested.connect(_show_events)
	navigation.calendar_requested.connect(_show_calendar)
	navigation.messages_requested.connect(_show_messages)

func _on_profile_identity_changed(_signed_in: bool, _player: Dictionary) -> void:
	_refresh_profile_progress()
	_refresh_currency_counts()

func _refresh_profile_avatar() -> void:
	var avatar_id := str(AuthGateway.current_player().get("avatar", "kael_avatar")) if AuthGateway.is_authenticated() else "kael_avatar"
	if avatar_id == _displayed_profile_avatar:
		return
	var portrait := get_node_or_null("ReferenceInterface/TopProfile/ProfileRow/AvatarFrame/KaelAvatar") as TextureRect
	if portrait == null:
		return
	var texture := preload("res://scripts/ui/social_portrait.gd").texture(avatar_id)
	if texture != null:
		portrait.texture = texture
		_displayed_profile_avatar = avatar_id

func _refresh_profile_progress() -> void:
	_refresh_profile_avatar()
	var details = get_node_or_null("ReferenceInterface/TopProfile/ProfileRow/ProfileDetails")
	if details == null:
		return
	var name_label := details.get_node_or_null("PlayerName") as Label
	if name_label != null:
		var display_name := str(AuthGateway.current_player().get("name", "")) if AuthGateway.is_authenticated() else "Traveler"
		name_label.text = display_name if not display_name.is_empty() else "Traveler"
	var level := maxi(1, int(GameState.profile.get("level", 1)))
	var xp := maxi(0, int(GameState.profile.get("xp", 0)))
	var bar := details.get_node("ExperienceBar") as ProgressBar
	bar.max_value = 250 + (level - 1) * 180
	bar.value = mini(xp, int(bar.max_value))
	bar.tooltip_text = "%d / %d XP" % [xp, int(bar.max_value)]
	var label := details.get_node("PlayerLevel") as Label
	label.text = "LEVEL %02d" % level

func _process(delta: float) -> void:
	_refresh_profile_progress()
	_notification_elapsed+=delta
	if _notification_elapsed>=0.25:
		_notification_elapsed=0.0
		_refresh_menu_notifications()

func _refresh_menu_notifications() -> void:
	var claimable:=bool(GameState.daily_reward_status().get("can_claim",false))
	$ReferenceInterface/LeftRail/EventsButton/Notification.visible=GameState.reward_domain.daily_quest_claimable_count()>0 or (AuthGateway.is_authenticated() and (AuthGateway.online_daily_claimable>0 or AuthGateway.online_weekly_claimable>0 or AuthGateway.online_monthly_claimable>0 or AuthGateway.online_achievement_claimable>0))
	$ReferenceInterface/LeftRail/CalendarButton/Notification.visible=claimable
	$ReferenceInterface/LeftRail/CalendarButton.tooltip_text="Daily reward ready to claim" if claimable else "Daily reward already claimed"
	_on_friend_notification(AuthGateway.incoming_friend_requests if AuthGateway.is_authenticated() else 0)
	if AuthGateway.is_authenticated() and AuthGateway.online_season_claimable+AuthGateway.online_season_challenge_claimable>0:
		var friend_button:Button=$ReferenceInterface/LeftRail/FriendsButton
		friend_button.tooltip_text="Friends & Profile | Season rewards ready"
		if AuthGateway.incoming_friend_requests==0:
			friend_button.get_node("Notification").visible=true
			friend_button.get_node("Notification/Count").text=str(mini(99,AuthGateway.online_season_claimable+AuthGateway.online_season_challenge_claimable))
	else:
		$ReferenceInterface/LeftRail/FriendsButton.tooltip_text="Friends & Profile"

	_on_chat_notification(AuthGateway.unread_private_messages if AuthGateway.is_authenticated() else 0)

func _on_friend_notification(count: int) -> void:
	var badge: Panel=$ReferenceInterface/LeftRail/FriendsButton/Notification
	badge.visible=count>0
	badge.get_node("Count").text="99+" if count>99 else str(count)

func _on_chat_notification(count: int) -> void:
	var badge: Panel=$ReferenceInterface/BottomNavigation/CommunicationButton/Notification
	badge.visible=count>0
	badge.get_node("Count").text="99+" if count>99 else str(count)


func _refresh_currency_counts() -> void:
	var hub := get_node_or_null("ReferenceInterface")
	var game_state := get_node_or_null("/root/GameState")
	if hub == null or game_state == null:
		return
	var inventory_domain: Node = game_state.get("inventory_domain")
	if inventory_domain == null:
		return
	var crystals := hub.get_node_or_null("CurrencyBar/PremiumCurrency") as Button
	var gold := hub.get_node_or_null("CurrencyBar/GoldCurrency") as Button
	var paid_currency := hub.get_node_or_null("CurrencyBar/PaidCurrency") as Button
	var online := AuthGateway.is_authenticated()
	for pair in [[crystals,"crystals"],[gold,"gold"],[paid_currency,"paid_moonstones"]]:
		var button: Button = pair[0]
		var id: String = pair[1]
		if button == null: continue
		if online:
			button.text = "..." if AuthGateway.online_wallet.is_empty() else UIFactory.number(int(AuthGateway.online_currencies.get(id,0)))
			button.tooltip_text = "Online wallet: " + id.replace("_"," ")
		else:
			button.text = UIFactory.number(int(inventory_domain.call("currency",id)))
			button.tooltip_text = "Local story wallet: " + id.replace("_"," ")
		if id == "paid_moonstones" and OS.get_name() not in ["Android","iOS","Web"]:
			button.text += "  +"
			button.tooltip_text = "Open Paid Moonstone Shop (test purchases only)"

func _open_profile() -> void:
	if AuthGateway.is_authenticated():
		if has_node("PlayerProfileOverlay"):
			return
		var overlay := preload("res://scenes/ui/social_screen.tscn").instantiate()
		overlay.name = "PlayerProfileOverlay"
		overlay.z_index = 120
		overlay.private_chat_requested.connect(_open_profile_chat.bind(overlay))
		add_child(overlay)
		return
	_open_profile_account()

func _open_profile_chat(player_id: String, previous: OverlayScreen) -> void:
	if not AuthGateway.is_authenticated() or not is_instance_valid(previous):return
	var chat:=preload("res://scenes/ui/chat_screen.tscn").instantiate()
	chat.set_initial_recipient(player_id)
	previous.name="ClosingPlayerProfile"
	chat.name="PlayerProfileOverlay"
	chat.z_index = 120
	add_child(chat)
	previous.close_screen()

func _open_profile_account() -> void:
	if has_node("ProfileAccountOverlay"):
		return
	var packed := load("res://scenes/online/account_screen.tscn") as PackedScene
	if packed == null:
		overlays.show_notice("Account unavailable", "The account screen could not be loaded.")
		return
	var account := packed.instantiate() as Control
	account.name = "ProfileAccountOverlay"
	account.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	account.z_index = 120
	add_child(account)
	account.closed.connect(account.queue_free)
	account.account_authenticated.connect(_on_profile_account_authenticated.bind(account))
	account.call_deferred("show_registration")

func _on_profile_account_authenticated(player: Dictionary, account: Control) -> void:
	_refresh_profile_progress()
	_refresh_currency_counts()
	EventBus.toast_requested.emit("Account connected: %s" % str(player.get("name", "Wanderer")))
	if is_instance_valid(account):
		account.queue_free()
	_open_profile()

func _show_paid_currency() -> void:
	if OS.get_name() in ["Android","iOS","Web"]: return
	if not AuthGateway.is_authenticated():
		overlays.show_notice("Moonstone Shop", "Sign in to your online account to buy test Moonstones.")
		return
	overlays.open_path("res://scenes/ui/moonstone_shop.tscn", "MoonstoneShopOverlay")

func _on_menu_character_changed(id: String) -> void:
	var key := "kael" if id.begins_with("kael_") else ("ravienna" if id in ["","default","ravienna"] else id)
	if key != _menu_dialogue_key:
		_menu_dialogue_key = key
		ravienna_line_index = 0
	_show_menu_dialogue_line()

func _menu_dialogue_lines() -> Array:
	return MENU_DIALOGUE.get(_menu_dialogue_key,ravienna_lines)

func _show_menu_dialogue_line() -> void:
	var lines := _menu_dialogue_lines()
	ravienna_line.text = str(lines[ravienna_line_index % lines.size()])
	_fit_ravienna_dialogue()

func _toggle_menu_dialogue() -> void:
	_dialogue_requested = not _dialogue_requested
	$RaviennaDialogue.visible = _dialogue_requested and not $MenuCharacterGallery.visible
	$MenuDialogueButton.text = "Hide dialogue" if _dialogue_requested else "Talk"
	if _dialogue_requested:
		_show_menu_dialogue_line()
		$RaviennaDialogueTimer.start()

func _on_menu_gallery_visibility(open: bool) -> void:
	$RaviennaDialogue.visible = _dialogue_requested and not open

func _advance_ravienna_dialogue() -> void:
	if not $RaviennaDialogue.visible:return
	var lines := _menu_dialogue_lines()
	ravienna_line_index = (ravienna_line_index + 1) % lines.size()
	_show_menu_dialogue_line()

func _fit_ravienna_dialogue() -> void:
	if ravienna_line == null:
		return
	var panel: TextureRect = $RaviennaDialogue
	var margin: MarginContainer = $RaviennaDialogue/DialogueMargin
	# The mirrored rose panel has its tail above the text; reserve space for the ornate frame.
	var horizontal := clampi(int(panel.size.x * 0.19),24,110)
	var top := clampi(int(panel.size.y * 0.35),24,85)
	var bottom := clampi(int(panel.size.y * 0.23),18,55)
	margin.add_theme_constant_override("margin_left",horizontal)
	margin.add_theme_constant_override("margin_right",horizontal)
	margin.add_theme_constant_override("margin_top",top)
	margin.add_theme_constant_override("margin_bottom",bottom)
	var length := ravienna_line.text.length()
	var font_size := 19
	if length > 105:
		font_size = 15
	elif length > 85:
		font_size = 16
	elif length > 65:
		font_size = 17
	elif length > 48:
		font_size = 18
	ravienna_line.add_theme_font_size_override("font_size", font_size)
	ravienna_line.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	ravienna_line.clip_text = false

func _show_mail() -> void:
	overlays.show_notice("Mail", "Your messages and rewards will appear here.")

func _show_events() -> void:
	overlays.open_path("res://scenes/ui/daily_quests_screen.tscn","DailyQuestsOverlay")

func _show_calendar() -> void:
	overlays.open_daily_rewards()

func _show_gifts() -> void:
	overlays.show_notice("Gifts", "Claimable gifts will appear here.")

func _show_achievements() -> void:
	overlays.open_path("res://scenes/ui/daily_quests_screen.tscn","DailyQuestsOverlay")
	var journal=get_node_or_null("DailyQuestsOverlay")
	if journal!=null and journal._operation.is_empty():journal._select_mode(true,false,false,true)

func _show_messages() -> void:
	if not AuthGateway.is_authenticated():
		_open_profile_account()
		return
	if has_node("PlayerProfileOverlay"):
		return
	var chat:=preload("res://scenes/ui/chat_screen.tscn").instantiate()
	chat.name="PlayerProfileOverlay"
	chat.z_index=120
	chat.set_initial_channel("private")
	add_child(chat)

func _open_pvp() -> void:
	var scene := load("res://scenes/online/pvp_screen.tscn") as PackedScene
	if scene == null:
		return
	var screen := scene.instantiate()
	add_child(screen)
	screen.z_index = 100
	screen.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
func _open_server_browser() -> void:
	if not AuthGateway.is_authenticated():
		overlays.show_notice("Sign in required", "Sign in to discover and join persistent regional worlds.")
		return
	var scene := load("res://scenes/online/server_browser_screen.tscn") as PackedScene
	if scene == null:
		overlays.show_notice("Worlds unavailable", "The persistent world browser could not be loaded.")
		return
	var screen := scene.instantiate()
	add_child(screen)
	screen.z_index = 110
	screen.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

func _show_combat() -> void:
	overlays.show_notice("Combat", "Enter the Story to begin your next encounter.")

func _show_castle() -> void:
	overlays.show_notice("Castle", "Your castle and royal gardens are waiting in the world.")

func _show_resources() -> void:
	overlays.show_notice("Resources", "Your gathered materials and currencies are shown here.")

func _show_crystals() -> void:
	overlays.show_notice("Crystals", "Premium currency balance and offers.")

func _show_gold() -> void:
	overlays.show_notice("Gold", "Your gold balance and spending options.")

func _on_quit() -> void:
	quit_requested.emit()
