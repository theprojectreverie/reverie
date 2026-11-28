class_name GachaBannerContentComponent
extends Node
## Owns the summon banner's featured-art, rates, pity and banner-detail presentation.

var screen: GachaScreen
var _scarlet_template: ScarletRequiemBannerTemplateComponent
var _live_art_cache: Dictionary = {}
var _live_art_pending := false
var _live_art_target: PortraitView
var _live_art_hash := ""
var _stage: Control
var _stage_banner := ""
const STAGE = preload("res://scenes/ui/components/summon_banner_stage.tscn")

func _apply_live_art(texture: Texture2D) -> void:
	if not is_instance_valid(_live_art_target): return
	_live_art_target.set_portrait_texture(texture)
	_live_art_target.show()

func _decode_live_art(bytes: PackedByteArray, expected: String) -> Texture2D:
	if bytes.is_empty() or bytes.size() > 1048576: return null
	var sha := HashingContext.new()
	sha.start(HashingContext.HASH_SHA256)
	sha.update(bytes)
	if sha.finish().hex_encode() != expected: return null
	var img := Image.new()
	if img.load_png_from_buffer(bytes) != OK or img.get_width() > 1024 or img.get_height() > 1024: return null
	return ImageTexture.create_from_image(img)

func _request_live_art() -> void:
	var hash := _live_art_hash
	if hash.length() != 64 or not hash.is_valid_hex_number(false): return
	if _live_art_cache.has(hash):
		_apply_live_art(_live_art_cache[hash])
		return
	var path := "user://live_banner_artwork.png"
	if FileAccess.file_exists(path):
		var file := FileAccess.open(path, FileAccess.READ)
		if file != null and file.get_length() <= 1048576:
			var cached := _decode_live_art(file.get_buffer(file.get_length()), hash)
			if cached != null:
				_live_art_cache[hash] = cached
				_apply_live_art(cached)
				return
	if _live_art_pending: return
	_live_art_pending = true
	var http := HTTPRequest.new()
	http.timeout = 10.0
	http.body_size_limit = 1048576
	http.max_redirects = 0
	add_child(http)
	if http.request(AuthGateway.api_base_url + "/v1/summon/artwork/" + hash, PackedStringArray(["Authorization: Bearer " + AuthGateway.access_token_for_request()])) != OK:
		http.queue_free()
		_live_art_pending = false
		return
	var response: Array = await http.request_completed
	http.queue_free()
	_live_art_pending = false
	if not is_inside_tree(): return
	if response[0] == HTTPRequest.RESULT_SUCCESS and response[1] == 200:
		var bytes: PackedByteArray = response[3]
		var texture := _decode_live_art(bytes, hash)
		if texture != null:
			if _live_art_cache.size() >= 4: _live_art_cache.clear()
			_live_art_cache[hash] = texture
			var file := FileAccess.open(path, FileAccess.WRITE)
			if file != null: file.store_buffer(bytes)
			if _live_art_hash == hash: _apply_live_art(texture)
	if _live_art_hash != hash: _request_live_art()


func _ready() -> void:
	_scarlet_template = get_node_or_null("ScarletRequiemTemplate") as ScarletRequiemBannerTemplateComponent


func bind(owner_screen: GachaScreen) -> void:
	screen = owner_screen

func close_drawer() -> void:
	if is_instance_valid(_stage): _stage.set_open(false, false)

func rebuild_main() -> void:
	var keep_open: bool = is_instance_valid(_stage) and _stage.opened and _stage_banner == screen._selected_banner and not screen._summon_busy and not is_instance_valid(screen._results_layer)
	var notice := screen._online_notice.get_parent().get_parent() as Control
	if notice.get_parent() != screen._main.get_parent(): notice.reparent(screen._main.get_parent(), false)
	_live_art_hash = ""
	_live_art_target = null
	UIFactory.clear(screen._main)
	_stage = null
	var hero := screen.get_node("BannerHero") as PortraitView
	hero.hide()
	hero.set_portrait_texture(null)
	screen._featured_id = ""
	screen._featured_premium = false
	var banner: Dictionary = screen.active_banner(screen._selected_banner)
	if banner.is_empty():
		screen._main.add_child(UIFactory.label("No summon banners are configured.", 13, UITheme.DANGER))
		return

	var featured: Array = banner.get("featured", [])
	var featured_id := str(featured[0]) if not featured.is_empty() else ""
	var featured_def: CharacterDef = ContentDB.get_character(featured_id)
	var featured_rarity := featured_def.rarity if featured_def != null else "legendary"
	screen._featured_id = featured_id
	screen._featured_premium = UITheme.is_premium_rarity(featured_rarity)
	hero.fit_mode = "art"
	hero.show_frame = false
	hero.show_rarity_effect = false
	hero.set_process(false)
	if featured_def != null:
		hero.setup_character(featured_def)
	else:
		hero.setup({}, "Human", "neutral", "legendary", 0)
	var directory := "res://assets/portraits/banners/"
	var backdrop := screen.get_node("SummoningChamberIllustration") as TextureRect
	# Zoom only the throne-room layer, symmetrically at every viewport size.
	var background_margin := 0.20 if screen._selected_banner == "crimson_oath" else 0.0
	backdrop.anchor_left = -background_margin
	backdrop.anchor_top = -background_margin
	backdrop.anchor_right = 1.0 + background_margin
	backdrop.anchor_bottom = 1.0 + background_margin
	backdrop.offset_left = 0.0
	backdrop.offset_top = 0.0
	backdrop.offset_right = 0.0
	backdrop.offset_bottom = 0.0
	# Use the approved Gerald composition placement, independently of the backdrop.
	var gerald_layout := screen._selected_banner == "flamebound_guardian"
	hero.anchor_left = 0.0
	hero.anchor_right = 0.84375 if gerald_layout else 1.0
	hero.anchor_top = 0.07916667 if gerald_layout else 0.0
	hero.anchor_bottom = 0.82916667 if gerald_layout else 1.0
	hero.offset_left = 0.0
	hero.offset_right = 0.0
	hero.offset_top = 0.0 if gerald_layout else 55.0
	hero.offset_bottom = 0.0 if gerald_layout else -55.0
	var background_path := directory + screen._selected_banner + "_background.png"
	backdrop.texture = load(background_path) as Texture2D if ResourceLoader.exists(background_path) else preload("res://assets/ui/backgrounds/gothic_moonlit_summoning_cathedral.png")
	var character_path := directory + ("cassien_legendary_character.png" if screen._selected_banner == "crimson_oath" else featured_id + "_character.png")
	if screen._selected_banner == "eclipse_sovereign": character_path = directory + "ravienna_character.png"
	if screen._selected_banner == "lily_of_shadows": character_path = directory + "elathra_character.png"
	if ResourceLoader.exists(character_path):
		hero.set_portrait_texture(load(character_path) as Texture2D)
	elif not preload("res://scripts/art/approved_character_portraits.gd").is_approved(hero.portrait_texture):
		var fallback := "res://assets/portraits/summon/%s.png" % featured_id
		if ResourceLoader.exists(fallback): hero.set_portrait_texture(load(fallback) as Texture2D)
	hero.visible = hero.portrait_texture != null
	# Mirene uses the approved complete swing composition (no duplicate hero layer).
	if featured_id == "mirene" or featured_id.begins_with("mirene_"):
		var mirene_banner := directory + "mirene_background.png"
		if ResourceLoader.exists(mirene_banner):
			backdrop.texture = load(mirene_banner) as Texture2D
			hero.set_portrait_texture(null)
			hero.hide()
	# The approved Lilith composition is a full image until its separate layer exists.
	if screen._selected_banner == "moonlit_requiem" and not ResourceLoader.exists(character_path):
		hero.set_portrait_texture(null)
		hero.hide()
	_live_art_target = hero
	_live_art_hash = str(banner.get("artwork", ""))
	if not _live_art_hash.is_empty(): _request_live_art()
	_stage = STAGE.instantiate()
	screen._main.add_child(_stage)
	_stage_banner = screen._selected_banner
	var info: VBoxContainer = _stage.info
	info.add_child(UIFactory.heading(str(banner.get("name", screen._selected_banner)), 22, UITheme.GOLD_BRIGHT))
	info.add_child(UIFactory.wrapped(str(banner.get("subtitle", "")), 13, UITheme.TEXT))
	if banner.has("endsAt"):
		info.add_child(UIFactory.wrapped("Available until " + str(banner.endsAt).replace("T", " ").replace("Z", " UTC") + " (crystal summons only)", 12, UITheme.GOLD))
	if featured_def != null:
		info.add_child(UIFactory.label("Featured: " + featured_def.display_name, 15, UITheme.GOLD))
		info.add_child(UIFactory.rarity_chip(featured_def.rarity))
		info.add_child(featured_skill_panel(featured_def))
	notice.reparent(info, false)
	notice.show()

	var wallet := HFlowContainer.new()
	wallet.add_theme_constant_override("h_separation",8)
	wallet.add_theme_constant_override("v_separation",6)
	wallet.add_child(_currency_icon_chip("crystals", screen.summon_currency("crystals"), UITheme.TEAL))
	wallet.add_child(_currency_icon_chip("gold", screen.summon_currency("gold"), UITheme.GOLD))
	wallet.add_child(_currency_icon_chip("paid_moonstones", screen.summon_currency("paid_moonstones"), UITheme.VIOLET))
	info.add_child(wallet)
	var events: Array = screen._summon_flow.online_state.get("liveEvents", [])
	if not events.is_empty():
		info.add_child(UIFactory.heading("Live events", 18, UITheme.GOLD))
		for event in events:
			var reward: Dictionary = event.get("reward", {})
			info.add_child(UIFactory.wrapped(str(event.get("name", "Event")) + " — " + str(event.get("description", "")) + "\n" + str(reward.get("amount", 0)) + " " + str(reward.get("currency", "")) + " • Ends " + str(event.get("endsAt", "")), 13, UITheme.TEXT_DIM))
			var claimed := bool(event.get("claimed", false))
			var eligible := bool(event.get("eligible", false))
			if event.has("objective"):
				info.add_child(UIFactory.wrapped("Verified victories: %d / %d" % [int(event.get("progress",0)),int(event.get("required",0))], 13, UITheme.GOLD))
			var claim := UIFactory.button("Reward claimed" if claimed else ("Claim event reward" if eligible else "Complete event objective"))
			claim.disabled = claimed or not eligible or not screen._account_state_ready() or screen._summon_busy or screen._upgrade_busy
			claim.pressed.connect(screen._claim_live_event.bind(str(event.get("id", ""))))
			info.add_child(claim)
			if event.has("shop"):
				var offer: Dictionary = event.shop
				var item_id := str(offer.get("item", ""))
				var item_name := str(ContentDB.get_item(item_id).get("name", item_id))
				var price := int(offer.get("price",0))
				var currency := str(offer.get("currency", ""))
				var bought := bool(event.get("purchased",false))
				var buy := UIFactory.button("Offer purchased" if bought else "Buy %d × %s — %d %s" % [int(offer.get("quantity",0)),item_name,price,currency])
				buy.disabled = bought or not eligible or not screen._account_state_ready() or screen._summon_busy or screen._upgrade_busy or screen.summon_currency(currency)<price
				buy.pressed.connect(screen._confirm_live_event_purchase.bind(str(event.get("id","")),offer.duplicate(true),item_name))
				info.add_child(buy)


	info.add_child(UIFactory.label("ORDINARY CRYSTALS", 11, UITheme.TEXT_DIM))
	var cost: Dictionary = banner.get("cost", {})
	var currency_id := str(cost.get("currency", "crystals"))
	var single_cost := int(cost.get("single", 0))
	var ten_cost := int(cost.get("ten", 0))
	var buttons := BoxContainer.new()
	buttons.vertical = false
	buttons.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	buttons.add_theme_constant_override("separation",10)
	var single := UIFactory.button("Summon ×1 — %s" % UIFactory.number(single_cost))
	_apply_currency_button_icon(single, currency_id)
	single.custom_minimum_size = Vector2(0, 48)
	single.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	single.disabled = not screen.summon_available(1, single_cost, currency_id)
	single.pressed.connect(func() -> void: screen._pull(1))
	buttons.add_child(single)
	var ten := UIFactory.button("Summon ×10 — %s" % UIFactory.number(ten_cost), true)
	_apply_currency_button_icon(ten, currency_id)
	ten.custom_minimum_size = Vector2(0, 48)
	ten.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	ten.disabled = not screen.summon_available(10, ten_cost, currency_id)
	ten.pressed.connect(func() -> void: screen._pull(10))
	buttons.add_child(ten)
	_stage.actions.add_child(buttons)
	var paid_progress := screen.paid_summon_progress()
	var paid_box := UIFactory.vbox(6)
	paid_box.name = "PaidMilestone"
	if preload("res://scripts/online/connection_profile.gd").is_public_alpha():
		paid_box.add_child(UIFactory.wrapped("Paid summons are currently unavailable in public alpha. Ordinary crystal summons are available. Recover any rejected pending request using Retry.",13,UITheme.GOLD))
	if screen.paid_guarantee_verified():
		paid_box.add_child(pity_row("Featured character guarantee",paid_progress,100,"%d / 100" % paid_progress,UITheme.VIOLET))
	else:
		paid_box.add_child(UIFactory.wrapped("Paid guarantee progress unavailable. Sign in or reconnect to verify your server counter.",13,UITheme.GOLD))
	paid_box.add_child(UIFactory.wrapped("Every 100th Paid Moon Stone summon guarantees the current banner character. Counts across banners; ordinary crystals do not count. Existing featured characters may repeat.",12,UITheme.TEXT_DIM))
	if screen.paid_guarantee_verified():
		paid_box.add_child(UIFactory.wrapped("%d paid summons until the featured character is guaranteed." % (100 - paid_progress),12,UITheme.VIOLET))
	var paid_cost: Dictionary = banner.get("cost",{})
	var paid_buttons := BoxContainer.new()
	paid_buttons.vertical = false
	paid_buttons.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	paid_buttons.add_theme_constant_override("separation",8)
	for count in [1,10]:
		var price := int(paid_cost.get("single" if count==1 else "ten",0))
		var button := UIFactory.button("Paid x%d - %s" % [count,UIFactory.number(price)],count==10)
		button.name = "PaidPull%d" % count
		if not screen._summon_flow.pending_online.is_empty() and screen.summon_available(count,price,"paid_moonstones"):
			button.text = "Retry paid x%d" % count
		button.custom_minimum_size = Vector2(0,48)
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.disabled = price<=0 or not screen.summon_available(count,price,"paid_moonstones")
		_apply_currency_button_icon(button,"paid_moonstones")
		button.pressed.connect(screen._pull.bind(count,true))
		paid_buttons.add_child(button)
	_stage.actions.add_child(paid_buttons)
	if OS.get_name() not in ["Android","iOS","Web"]:
		var shop := UIFactory.button("Moonstone Shop (test mode)")
		shop.name = "MoonstoneShopButton"
		shop.custom_minimum_size = Vector2(0,44)
		shop.pressed.connect(screen._open_moonstone_shop)
		paid_box.add_child(shop)
	info.add_child(paid_box)

	var scarlet_palette := false
	var rates_panel := UIFactory.panel(
		Color("#180b16") if scarlet_palette else Color("#0e1628"),
		Color("#8f3b59") if scarlet_palette else UITheme.BORDER_SOFT,
		12, 1, 12
	)
	var rates_box := UIFactory.vbox(5)
	rates_box.add_child(UIFactory.label("CRYSTAL APPEARANCE RATES", 10, UITheme.TEXT_FAINT))
	var rates: Dictionary = banner.get("rates", {})
	for rarity in GachaService.RARITY_ORDER:
		var color := UITheme.rarity_color(rarity)
		var row := GachaScreen.RARITY_RATE_ROW_SCENE.instantiate() as RarityRateRow
		row.setup(rarity, UIFactory.percent(float(rates.get(rarity, 0.0)), 2), color)
		rates_box.add_child(row)
	var paid_rates: Dictionary = banner.get("paid_rates", {})
	if not paid_rates.is_empty():
		rates_box.add_child(UIFactory.label("PAID MOON STONE APPEARANCE RATES", 10, UITheme.TEXT_FAINT))
		for rarity in GachaService.RARITY_ORDER:
			var row := GachaScreen.RARITY_RATE_ROW_SCENE.instantiate() as RarityRateRow
			row.setup(rarity, UIFactory.percent(float(paid_rates.get(rarity, 0.0)), 2), UITheme.rarity_color(rarity))
			rates_box.add_child(row)
		rates_box.add_child(UIFactory.wrapped("Base rates before pity and guarantees. Featured Mythic chance: %s per paid pull." % UIFactory.percent(float(paid_rates.get("mythic", 0.0)) * float(banner.get("featured_rate", 0.5)), 2),12,UITheme.TEXT_DIM))
	var mob_note := UIFactory.wrapped("Common: mob materials. Rare and Epic: matching upgrade cards. 20 Rare = 1 Epic; 10 Epic = 1 Legendary; 7 Legendary acquisitions = 1 Mythic; 7 Mythic acquisitions = full ascension. Only Legendary and Mythic summons are playable.", 12, UITheme.TEXT_DIM)
	rates_box.add_child(mob_note)
	var stock: Dictionary = screen._summon_flow.online_state.get("cards", {})
	var card_lines: Array[String] = []
	for card_id in banner.get("upgrade_cards", {}):
		var amount := int(stock.get(card_id, 0))
		if amount > 0:
			card_lines.append("%s: %d/%d" % [ContentDB.get_item(card_id).get("name", card_id), amount, int(banner.upgrade_cards[card_id].cost)])
	var mythic_stock: Dictionary = screen._summon_flow.online_state.get("inventory", {})
	for legendary in banner.get("mythic_fusion", {}):
		var recipe: Dictionary = banner.mythic_fusion[legendary]
		var amount := int(mythic_stock.get(str(recipe.item), 0))
		if amount > 0:
			card_lines.append("%s: %d/%d" % [ContentDB.get_item(str(recipe.item)).get("name", recipe.item), amount, int(recipe.cost)])
	for mythic in banner.get("mythic_ascension", {}):
		var recipe: Dictionary = banner.mythic_ascension[mythic]
		var amount := int(mythic_stock.get(str(recipe.item), 0))
		if amount > 0:
			card_lines.append("%s: %d/%d" % [ContentDB.get_item(str(recipe.item)).get("name", recipe.item), amount, int(recipe.cost)])
	rates_box.add_child(UIFactory.wrapped("UPGRADE CARDS\n" + ("\n".join(card_lines) if not card_lines.is_empty() else "No cards collected yet."), 12, UITheme.TEXT_DIM))

	var guarantee_text := "10-pull guarantees at least one Epic or better." if bool(banner.get("ten_pull_epic_guarantee", false)) else "No Epic-or-better ten-pull guarantee is configured for this banner."
	var guarantee := UIFactory.wrapped(
		guarantee_text + " Featured share of matching rarity: %s. " % UIFactory.percent(float(banner.get("featured_rate", 0.5)), 2)
		+ "Hard pity: %d pulls. Featured guarantee: %d pulls." % [
			int(banner.get("hard_pity", 70)), int(banner.get("featured_pity", 140))
		],
		11,
		UITheme.TEXT_FAINT
	)
	rates_box.add_child(guarantee)
	rates_panel.add_child(rates_box)
	info.add_child(rates_panel)

	var pity: Dictionary = screen.summon_pity()
	var hard_pity := maxi(1, int(banner.get("hard_pity", 70)))
	var featured_pity := maxi(1, int(banner.get("featured_pity", 140)))
	var legendary_count := int(pity.get("legendary", 0))
	var featured_count := int(pity.get("featured", 0))
	var pity_panel := UIFactory.panel(
		Color("#180b16") if scarlet_palette else Color("#0e1628"),
		Color("#8f3b59") if scarlet_palette else UITheme.BORDER_SOFT,
		12, 1, 12
	)
	var pity_box := UIFactory.vbox(6)
	pity_box.add_child(UIFactory.label("PITY PROGRESS", 10, UITheme.TEXT_FAINT))
	pity_box.add_child(pity_row(
		"Legendary guarantee",
		legendary_count,
		hard_pity,
		"%d more pulls" % maxi(0, hard_pity - legendary_count),
		UITheme.GOLD
	))
	pity_box.add_child(pity_row(
		"Featured guarantee",
		featured_count,
		featured_pity,
		"%d more pulls" % maxi(0, featured_pity - featured_count),
		UITheme.VIOLET
	))
	pity_panel.add_child(pity_box)
	info.add_child(pity_panel)
	# Rates and pity are immediately accessible when the drawer opens.
	info.move_child(wallet, 1)
	info.move_child(rates_panel, 2)
	info.move_child(pity_panel, 3)
	for inner in info.find_children("*", "PanelContainer", true, false):
		var style := inner.get_theme_stylebox("panel").duplicate() as StyleBoxFlat
		if style != null:
			style.bg_color.a = minf(style.bg_color.a, 0.32)
			inner.add_theme_stylebox_override("panel", style)
	for label in info.find_children("*", "Label", true, false):
		if label.get_theme_color("font_color") in [UITheme.TEXT_FAINT, UITheme.TEXT_DIM] or label.get_theme_color("font_color").get_luminance() < 0.35:
			label.add_theme_color_override("font_color", Color("#e8e2f3"))
		if label.get_theme_font_size("font_size") < 13:
			label.add_theme_font_size_override("font_size", 13)
	_stage.set_open(keep_open, false)
	_stage._layout.call_deferred()





const CURRENCY_ICON_PATHS := {
	"paid_moonstones": "res://assets/ui/buttons/paid_moonstone.png",
	"gold": "res://assets/ui/currencies/gold.png",
	"crystals": "res://assets/ui/currencies/summoning_crystals.png",
	"ancient_coins": "res://assets/ui/currencies/ancient_coins.png",
	"gems": "res://assets/ui/currencies/gems.png",
	"guild_tokens": "res://assets/ui/currencies/guild_tokens.png",
	"event_tokens": "res://assets/ui/currencies/event_tokens.png",
}


func _currency_icon_chip(currency_id: String, amount: int, tint: Color) -> Control:
	var chip := load("res://scenes/ui/components/currency_chip.tscn").instantiate() as PanelContainer
	var icon := chip.get_node("Content/Dot") as TextureRect
	var texture_path := str(CURRENCY_ICON_PATHS.get(currency_id, ""))
	if not texture_path.is_empty() and ResourceLoader.exists(texture_path):
		icon.texture = load(texture_path) as Texture2D
		icon.custom_minimum_size = Vector2(26, 26)
		icon.modulate = Color.WHITE
	var label := chip.get_node("Content/ValueLabel") as Label
	label.text = UIFactory.number(amount)
	label.add_theme_color_override("font_color", tint)
	return chip


func _apply_currency_button_icon(button: Button, currency_id: String) -> void:
	var texture_path := str(CURRENCY_ICON_PATHS.get(currency_id, ""))
	if texture_path.is_empty() or not ResourceLoader.exists(texture_path):
		return
	button.icon = load(texture_path) as Texture2D
	button.add_theme_constant_override("icon_max_width", 22)
	button.icon_alignment = HORIZONTAL_ALIGNMENT_LEFT


func style_scarlet_pull_button(button: Button, primary: bool) -> void:
	var normal := StyleBoxFlat.new()
	normal.bg_color = Color("#70243f") if primary else Color("#351321")
	normal.border_color = Color("#e08aa5") if primary else Color("#a94a69")
	normal.set_border_width_all(1)
	normal.set_corner_radius_all(9)
	normal.content_margin_left = 10
	normal.content_margin_right = 10
	var hover := normal.duplicate() as StyleBoxFlat
	hover.bg_color = Color("#913453") if primary else Color("#512033")
	button.add_theme_stylebox_override("normal", normal)
	button.add_theme_stylebox_override("hover", hover)
	button.add_theme_stylebox_override("pressed", hover)
	button.add_theme_color_override("font_color", Color("#ffe8ef"))
	button.add_theme_color_override("font_hover_color", Color.WHITE)


func featured_skill_panel(definition: CharacterDef) -> Control:
	var panel := UIFactory.panel(Color("#100d1c"), Color(UITheme.VIOLET.r, UITheme.VIOLET.g, UITheme.VIOLET.b, 0.42), 10, 1, 10)
	var box := UIFactory.vbox(6)
	box.add_child(UIFactory.label("SIGNATURE ARTS", 10, UITheme.TEXT_FAINT))
	var skill_ids: Array = definition.skills.duplicate()
	skill_ids.append(definition.ultimate)
	var labels := ["ACTIVE I", "ACTIVE II", "ULTIMATE"]
	for index in mini(3, skill_ids.size()):
		var skill_id := str(skill_ids[index])
		var skill: SkillDef = ContentDB.get_skill(skill_id)
		if skill == null:
			continue
		var entry := UIFactory.vbox(2)
		var header := UIFactory.hbox(6)
		var tier_color := UITheme.GOLD_BRIGHT if index == 2 else UITheme.VIOLET
		header.add_child(UIFactory.label(labels[index], 9, tier_color))
		header.add_child(UIFactory.spacer())
		header.add_child(UIFactory.label(skill.display_name, 12, UITheme.TEXT))
		entry.add_child(header)
		entry.add_child(UIFactory.wrapped(skill.description, 10, UITheme.TEXT_DIM))
		box.add_child(entry)
		if index < mini(3, skill_ids.size()) - 1:
			box.add_child(UIFactory.separator())
	panel.add_child(box)
	return panel



func add_scarlet_requiem_banner_template(parent: VBoxContainer, banner: Dictionary, featured_def: CharacterDef, featured_glow: Color) -> void:
	if _scarlet_template != null:
		_scarlet_template.build(parent, banner, featured_def, featured_glow)


func pity_row(title: String, value: int, maximum: int, caption: String, color: Color) -> VBoxContainer:
	var box := UIFactory.vbox(3)
	var header := UIFactory.hbox(8)
	header.add_child(UIFactory.label(title, 11, UITheme.TEXT_DIM))
	header.add_child(UIFactory.spacer())
	header.add_child(UIFactory.label(caption, 10, color))
	box.add_child(header)
	var bar := UIFactory.bar(color, 8)
	bar.max_value = maximum
	bar.value = clampi(value, 0, maximum)
	box.add_child(bar)
	return box
