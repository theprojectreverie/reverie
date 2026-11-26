class_name GachaBannerContentComponent
extends Node
## Owns the summon banner's featured-art, rates, pity and banner-detail presentation.

var screen: GachaScreen
var _scarlet_template: ScarletRequiemBannerTemplateComponent

func _ready() -> void:
	_scarlet_template = get_node_or_null("ScarletRequiemTemplate") as ScarletRequiemBannerTemplateComponent


func bind(owner_screen: GachaScreen) -> void:
	screen = owner_screen

func rebuild_main() -> void:
	UIFactory.clear(screen._main)
	screen._featured_id = ""
	screen._featured_premium = false
	var banner: Dictionary = ContentDB.get_banner(screen._selected_banner)
	if banner.is_empty():
		screen._main.add_child(UIFactory.label("No summon banners are configured.", 13, UITheme.DANGER))
		return

	# ---------------------------------------------------------------- banner art
	var compact := screen.compact_summon_layout()
	var compact_column: VBoxContainer
	if compact:
		var shared_scroll := ScrollContainer.new()
		shared_scroll.name = "CompactSummonScroll"
		shared_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		shared_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
		shared_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
		screen._main.add_child(shared_scroll)
		compact_column = UIFactory.vbox(12)
		compact_column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		shared_scroll.add_child(compact_column)
	var art_scroll := ScrollContainer.new()
	art_scroll.custom_minimum_size = Vector2(390, 0)
	art_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	art_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	if not compact:
		screen._main.add_child(art_scroll)
	var art_panel := UIFactory.panel(Color("#0a0f1c"), Color(UITheme.GOLD.r, UITheme.GOLD.g, UITheme.GOLD.b, 0.28), 14, 1, 16)
	art_panel.custom_minimum_size = Vector2(0 if compact else 370, 0)
	if not compact:
		art_scroll.add_child(art_panel)
	var art := UIFactory.vbox(8)
	art_panel.add_child(art)

	var featured: Array = banner.get("featured", [])
	var featured_id := str(featured[0]) if not featured.is_empty() else ""
	var featured_def: CharacterDef = ContentDB.get_character(featured_id)
	var featured_rarity := featured_def.rarity if featured_def != null else "legendary"
	screen._featured_id = featured_id
	screen._featured_premium = UITheme.is_premium_rarity(featured_rarity)
	var featured_effect := UITheme.rarity_effect(featured_rarity)
	var featured_glow: Color = featured_effect.get("glow", UITheme.GOLD_BRIGHT)
	var featured_aura := clampf(float(featured_effect.get("aura", 0.0)), 0.0, 1.0)
	var portrait_backdrop := GachaScreen.FEATURED_BANNER_ART_FRAME_SCENE.instantiate() as PanelContainer
	portrait_backdrop.add_theme_stylebox_override(
		"panel",
		UITheme.style(
			Color(0.0, 0.0, 0.0, 0.0),
			Color(featured_glow.r, featured_glow.g, featured_glow.b, 0.42 + featured_aura * 0.38),
			14,
			2 if screen._featured_premium else 1,
			8
		)
	)
	var portrait_center := portrait_backdrop.get_node("FrameContent/PortraitCenter") as CenterContainer
	var portrait := GachaScreen.PORTRAIT_VIEW_SCENE.instantiate() as PortraitView
	# Use the complete 2:3 painted portrait as the card itself. Keep its native
	# aspect ratio so no generic ritual backdrop is exposed around the artwork.
	portrait.fit_mode = "art"
	var portrait_width := minf(320.0,maxf(140.0,screen.get_viewport_rect().size.x - 112.0)) if compact else 320.0
	portrait.custom_minimum_size = Vector2(portrait_width, portrait_width * 1.5)
	portrait.show_frame = false
	portrait.show_rarity_effect = false
	if featured_def != null:
		portrait.setup_character(featured_def)
		var featured_portrait_path := "res://assets/portraits/summon/%s.png" % featured_def.id
		if ResourceLoader.exists(featured_portrait_path):
			var featured_texture := load(featured_portrait_path) as Texture2D
			if featured_texture != null:
				portrait.set_portrait_texture(featured_texture)
	else:
		portrait.setup({}, "Human", "neutral", "legendary", 0)
	# Match the frame to the complete artwork instead of forcing every painting
	# into a 2:3 slot. This keeps hats, horns and full-body designs intact.
	if portrait.portrait_texture != null:
		var native := portrait.portrait_texture.get_size()
		var available_height := clampf(screen.get_viewport_rect().size.y - 350.0, 220.0, 480.0)
		var fitted_size := native * minf(portrait_width / native.x, available_height / native.y)
		portrait.custom_minimum_size = fitted_size.round()
		portrait_backdrop.custom_minimum_size = fitted_size + Vector2(16, 16)
		portrait_backdrop.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		portrait_backdrop.get_node("FrameContent").custom_minimum_size = fitted_size
	portrait_center.add_child(portrait)
	portrait.set_process(false)
	art.add_child(portrait_backdrop)

	var banner_name := UIFactory.heading(str(banner.get("name", screen._selected_banner)), 24, UITheme.GOLD_BRIGHT)
	banner_name.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	art.add_child(banner_name)
	var subtitle := UIFactory.label(str(banner.get("subtitle", "")), 12, UITheme.TEXT_DIM)
	subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	subtitle.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	art.add_child(subtitle)
	var chips := UIFactory.hbox(6)
	chips.alignment = BoxContainer.ALIGNMENT_CENTER
	chips.add_child(UIFactory.chip(str(banner.get("type", "standard")).capitalize(), UITheme.VIOLET))
	if featured_def != null:
		chips.add_child(UIFactory.rarity_chip(featured_def.rarity))
	art.add_child(chips)
	if featured_def != null:
		var featured_label := UIFactory.label("Featured · " + featured_def.display_name, 13, UITheme.GOLD)
		featured_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		art.add_child(featured_label)

	if featured_def != null:
		art.add_child(featured_skill_panel(featured_def))

	# --------------------------------------------------------------- info column
	var info_scroll := ScrollContainer.new()
	info_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	info_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	info_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	if not compact:
		screen._main.add_child(info_scroll)
	var info := UIFactory.vbox(10)
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	if compact:
		compact_column.add_child(info)
		compact_column.add_child(art_panel)
		art_scroll.free()
		info_scroll.free()
	else:
		info_scroll.add_child(info)

	var wallet := HFlowContainer.new()
	wallet.add_theme_constant_override("h_separation",8)
	wallet.add_theme_constant_override("v_separation",6)
	wallet.add_child(_currency_icon_chip("crystals", screen.summon_currency("crystals"), UITheme.TEAL))
	wallet.add_child(_currency_icon_chip("gold", screen.summon_currency("gold"), UITheme.GOLD))
	wallet.add_child(_currency_icon_chip("paid_moonstones", screen.summon_currency("paid_moonstones"), UITheme.VIOLET))
	info.add_child(wallet)
	info.add_child(UIFactory.label("ORDINARY CRYSTALS", 11, UITheme.TEXT_DIM))
	var cost: Dictionary = banner.get("cost", {})
	var currency_id := str(cost.get("currency", "crystals"))
	var single_cost := int(cost.get("single", 0))
	var ten_cost := int(cost.get("ten", 0))
	var buttons := BoxContainer.new()
	buttons.vertical = compact and screen.get_viewport_rect().size.x < 520.0
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
	info.add_child(buttons)
	var paid_progress := screen.paid_summon_progress()
	var paid_box := UIFactory.vbox(6)
	paid_box.name = "PaidMilestone"
	if screen.paid_guarantee_verified():
		paid_box.add_child(pity_row("Featured character guarantee",paid_progress,100,"%d / 100" % paid_progress,UITheme.VIOLET))
	else:
		paid_box.add_child(UIFactory.wrapped("Paid guarantee progress unavailable. Sign in or reconnect to verify your server counter.",13,UITheme.GOLD))
	paid_box.add_child(UIFactory.wrapped("Every 100th Paid Moon Stone summon guarantees the current banner character. Counts across banners; ordinary crystals do not count. Existing featured characters may repeat.",12,UITheme.TEXT_DIM))
	if screen.paid_guarantee_verified():
		paid_box.add_child(UIFactory.wrapped("%d paid summons until the featured character is guaranteed." % (100 - paid_progress),12,UITheme.VIOLET))
	var paid_cost: Dictionary = banner.get("cost",{})
	var paid_buttons := BoxContainer.new()
	paid_buttons.vertical = compact and screen.get_viewport_rect().size.x < 520.0
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
	paid_box.add_child(paid_buttons)
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
	rates_box.add_child(UIFactory.label("APPEARANCE RATES", 10, UITheme.TEXT_FAINT))
	var rates: Dictionary = banner.get("rates", {})
	for rarity in GachaService.RARITY_ORDER:
		var color := UITheme.rarity_color(rarity)
		var row := GachaScreen.RARITY_RATE_ROW_SCENE.instantiate() as RarityRateRow
		row.setup(rarity, UIFactory.percent(float(rates.get(rarity, 0.0))), color)
		rates_box.add_child(row)
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
		guarantee_text + " Featured rate-up: %s. " % UIFactory.percent(float(banner.get("featured_rate", 0.5)), 0)
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
