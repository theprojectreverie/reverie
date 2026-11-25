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
var ravienna_line_index := 0

func _ready() -> void:
	UIFactory.set_full_rect(self)
	theme = UITheme.build()
	_fit_ravienna_dialogue()
	navigation.bind(self)
	skin.bind(self)
	_refresh_profile_progress()
	_refresh_currency_counts()
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
	navigation.mail_requested.connect(_show_mail)
	navigation.events_requested.connect(_show_events)
	navigation.calendar_requested.connect(_show_calendar)
	navigation.gifts_requested.connect(_show_gifts)
	navigation.achievements_requested.connect(_show_achievements)
	navigation.messages_requested.connect(_show_messages)
	navigation.combat_requested.connect(_show_combat)
	navigation.castle_requested.connect(_show_castle)
	navigation.resources_requested.connect(_show_resources)
	navigation.paid_currency_requested.connect(_show_paid_currency)
	navigation.crystals_requested.connect(_show_crystals)
	navigation.gold_requested.connect(_show_gold)

func _refresh_profile_progress() -> void:
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

func _process(_delta: float) -> void:
	_refresh_profile_progress()

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
	if crystals != null:
		crystals.text = UIFactory.number(int(inventory_domain.call("currency", "crystals")))
	if gold != null:
		gold.text = UIFactory.number(int(inventory_domain.call("currency", "gold")))
	if paid_currency != null:
		paid_currency.text = UIFactory.number(int(inventory_domain.call("currency", "paid_moonstones")))

func _open_profile() -> void:
	if AuthGateway.is_authenticated():
		if has_node("PlayerProfileOverlay"):
			return
		var overlay := preload("res://scenes/ui/player_profile_overlay.tscn").instantiate()
		add_child(overlay)
		return
	_open_profile_account()

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
	overlays.show_notice("Paid Moonstones", "Premium-only currency. Your balance is shown here; purchases can be connected when the store is ready.")

func _advance_ravienna_dialogue() -> void:
	ravienna_line_index = (ravienna_line_index + 1) % ravienna_lines.size()
	ravienna_line.text = ravienna_lines[ravienna_line_index]
	_fit_ravienna_dialogue()

func _fit_ravienna_dialogue() -> void:
	if ravienna_line == null:
		return
	var length := ravienna_line.text.length()
	var font_size := 17
	if length > 105:
		font_size = 12
	elif length > 85:
		font_size = 13
	elif length > 65:
		font_size = 14
	elif length > 48:
		font_size = 15
	ravienna_line.add_theme_font_size_override("font_size", font_size)
	ravienna_line.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	ravienna_line.clip_text = false

func _show_mail() -> void:
	overlays.show_notice("Mail", "Your messages and rewards will appear here.")

func _show_events() -> void:
	overlays.show_notice("Events", "Limited-time events will appear here.")

func _show_calendar() -> void:
	overlays.open_daily_rewards()

func _show_gifts() -> void:
	overlays.show_notice("Gifts", "Claimable gifts will appear here.")

func _show_achievements() -> void:
	overlays.show_notice("Achievements", "Your milestones and rewards will appear here.")

func _show_messages() -> void:
	overlays.show_notice("Messages", "Your conversations will appear here.")

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
