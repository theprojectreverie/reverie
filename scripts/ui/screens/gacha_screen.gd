class_name GachaScreen
extends OverlayScreen
## Summon screen. Rates, pools, pity thresholds and costs are read verbatim from
## resources/data/banners.json. The pull itself is handled by GachaService.
##
## OFFLINE NOTE: this vertical slice rolls on the client. Phase 12 moves the RNG
## and ownership grant behind the authoritative server boundary.

const FEATURED_BANNER_ART_FRAME_SCENE: PackedScene = preload("res://scenes/ui/components/featured_banner_art_frame.tscn")
const FEATURED_BANNER_ARTWORK_SCENE: PackedScene = preload("res://scenes/ui/components/featured_banner_artwork.tscn")
const PORTRAIT_VIEW_SCENE: PackedScene = preload("res://scenes/ui/components/portrait_view.tscn")
const GACHA_LAYOUT_SCENE: PackedScene = preload("res://scenes/ui/components/gacha_screen_layout.tscn")
const SUMMON_REVEAL_SCENE: PackedScene = preload("res://scenes/ui/components/summon_reveal_overlay.tscn")
const SUMMON_RESULTS_SCENE: PackedScene = preload("res://scenes/ui/components/summon_results_overlay.tscn")
const SUMMON_RESULT_CARD_SCENE: PackedScene = preload("res://scenes/ui/components/summon_result_card.tscn")
const RARITY_RATE_ROW_SCENE: PackedScene = preload("res://scenes/ui/components/rarity_rate_row.tscn")
const CHAMBER_ATMOSPHERE_SCENE: PackedScene = preload("res://scenes/ui/components/summoning_chamber_atmosphere.tscn")

var _tabs: HFlowContainer
var _main: HBoxContainer
var _selected_banner: String = ""
var _results_layer: Control
var _summon_busy: bool = false
var _previous_music := ""
var _online_mode := true
var collection_only := false
var _embedded_collection_body: ScrollContainer
var _collection_open := false

func _collection_body() -> ScrollContainer:
	if is_instance_valid(_embedded_collection_body):return _embedded_collection_body
	return get_node("OnlineRosterDialog/BodyScroll") as ScrollContainer

func _collection_visible() -> bool:
	return _collection_open and _collection_body().is_visible_in_tree() if collection_only else get_node("OnlineRosterDialog").visible
var _online_notice: Label
var _online_switch: CheckButton
var _online_roster: Button
var _history_button: Button
var _pending_recovery: Button
var _collection_retry: Button
var _online_selected: Dictionary = {}
var _upgrade_busy := false
var _live_refresh_pending := false
var _live_refresh_at := 0
var _live_poll_at := 0
var _resize_queued := false
var _resize_pending := false

# Summon presentation state. Featured portrait assets are resolved by the
# banner content component; missing optional portraits retain the safe fallback.
var _featured_id: String = ""
var _featured_premium: bool = false
var _reveal_animations: int = 0
var _result_cards: int = 0
var _banner_content: GachaBannerContentComponent
var _summon_flow: GachaSummonFlowComponent


func _ready() -> void:
	_banner_content = get_node_or_null("BannerContent") as GachaBannerContentComponent
	_summon_flow = get_node_or_null("SummonFlow") as GachaSummonFlowComponent
	if _banner_content == null or _summon_flow == null:
		push_error("GachaScreen requires authored BannerContent and SummonFlow components.")
		return
	_banner_content.bind(self)
	_summon_flow.bind(self)
	_online_mode = true
	super._ready()
	var roster_dialog: AcceptDialog = get_node("OnlineRosterDialog")
	roster_dialog.theme = theme
	roster_dialog.add_theme_stylebox_override("panel",UITheme.style(UITheme.PANEL_DEEP,UITheme.VIOLET,12,1,14))
	roster_dialog.add_theme_stylebox_override("embedded_border",UITheme.style(UITheme.PANEL_DEEP,UITheme.VIOLET,12,1,14))
	var atmosphere := get_node_or_null("SummoningChamberAtmosphere") as Control
	if atmosphere == null:
		push_error("GachaScreen requires its authored SummoningChamberAtmosphere scene.")
		return
	atmosphere.z_index = -1
	if collection_only:
		atmosphere.hide()
		atmosphere.set_process(false)
	if not collection_only:
		_previous_music = AudioDirector.begin_screen_music("summoning")
	# OverlayScreen normally dims the whole scene and places an opaque glass
	# panel over it. Summoning is a full-scene destination: soften that dimmer
	# and turn the shell panel into translucent glass so the chamber is visible.
	var shell_dim := get_node_or_null("OverlayShell/Dim") as ColorRect
	if shell_dim != null:
		shell_dim.color = Color(0.01, 0.012, 0.035, 0.24)
	var shell_panel := get_node_or_null("OverlayShell/Margin/Panel") as PanelContainer
	if shell_panel != null:
		var glass := StyleBoxFlat.new()
		glass.bg_color = Color(0.025, 0.018, 0.055, 0.94 if collection_only else 0.58)
		glass.border_color = Color(0.72, 0.56, 0.91, 0.52)
		glass.set_border_width_all(1)
		glass.set_corner_radius_all(16)
		glass.content_margin_left = 10 if compact_summon_layout() else 18
		glass.content_margin_right = glass.content_margin_left
		glass.content_margin_top = glass.content_margin_left
		glass.content_margin_bottom = glass.content_margin_left
		shell_panel.add_theme_stylebox_override("panel", glass)
	_apply_summon_shell_size()
	get_viewport().size_changed.connect(_queue_summon_resize)
	# Summoning chamber key art is an authored TextureRect in gacha_screen.tscn.
	# Keep the node in the editor; runtime logic only controls its availability.
	var backdrop := get_node_or_null("SummoningChamberIllustration") as TextureRect
	if backdrop != null:
		backdrop.visible = backdrop.texture != null
	if not EventBus.currency_changed.is_connected(_on_wallet_changed):
		EventBus.currency_changed.connect(_on_wallet_changed)
	AuthGateway.online_wallet_changed.connect(_queue_online_refresh)
	AuthGateway.authentication_changed.connect(_clear_progress_comparison)
	if AuthGateway.is_authenticated():
		_load_default_online.call_deferred()


func _exit_tree() -> void:
	if not collection_only:
		AudioDirector.end_screen_music("summoning", _previous_music)
	if EventBus.currency_changed.is_connected(_on_wallet_changed):
		EventBus.currency_changed.disconnect(_on_wallet_changed)
	if not collection_only:
		AudioDirector.stop_summon_ritual_ambience()


func _apply_summon_shell_size() -> void:
	var compact := compact_summon_layout()
	var margin := get_node("OverlayShell/Margin") as MarginContainer
	var inset := 10.0 if compact else 34.0
	margin.offset_left = inset
	margin.offset_right = -inset
	margin.offset_top = inset
	margin.offset_bottom = -inset
	get_node("OverlayShell/Margin/Panel/Root/Header/Titles/Subtitle").visible = not compact and not screen_subtitle.is_empty()
	get_node("OverlayShell/Margin/Panel/Root/Header/CloseButton").custom_minimum_size = Vector2(82 if compact else 116,48)
	var panel := get_node("OverlayShell/Margin/Panel") as PanelContainer
	var style := panel.get_theme_stylebox("panel").duplicate() as StyleBoxFlat
	if style != null:
		var padding := 10.0 if compact else 18.0
		for side in [SIDE_LEFT,SIDE_TOP,SIDE_RIGHT,SIDE_BOTTOM]:
			style.set_content_margin(side,padding)
		panel.add_theme_stylebox_override("panel",style)
	var shop := header_actions.get_node_or_null("HeaderMoonstoneShop")
	if shop != null: shop.visible = not compact

func _queue_summon_resize() -> void:
	if _resize_queued: return
	_resize_queued = true
	_apply_summon_resize.call_deferred()

func _apply_summon_resize() -> void:
	_resize_queued = false
	if not is_inside_tree() or _closing: return
	_apply_summon_shell_size()
	_summon_flow.resize_results()
	if _summon_busy:
		_resize_pending = true
		return
	_resize_pending = false
	_refresh()

func _queue_online_refresh() -> void:
	if not _online_mode or not AuthGateway.is_authenticated(): return
	_live_refresh_pending = true
	_live_refresh_at = Time.get_ticks_msec() + 300

func _process(_delta: float) -> void:
	var now := Time.get_ticks_msec()
	var atmosphere := get_node_or_null("SummoningChamberAtmosphere") as Control
	if atmosphere != null:
		var show_atmosphere := not collection_only and not is_instance_valid(_results_layer)
		if atmosphere.visible != show_atmosphere: atmosphere.visible = show_atmosphere
	if _online_mode and AuthGateway.is_authenticated() and now >= _live_poll_at:
		_live_poll_at = now + (10000 if GraphicsSettings.quality == 0 else 5000)
		if not _live_refresh_pending: _queue_online_refresh()
	if not _live_refresh_pending or now < _live_refresh_at: return
	if _summon_busy or _upgrade_busy or _summon_flow == null or _summon_flow.online_loading or _summon_flow.online_request_busy: return
	_live_refresh_pending = false
	if _online_mode and AuthGateway.is_authenticated():
		await _refresh_live_collection()

func _refresh_live_collection() -> void:
	var before: Dictionary = _summon_flow.online_state
	var was_fresh := _summon_flow.online_state_fresh
	if not await _summon_flow.refresh_online_state():
		if is_inside_tree():
			_refresh()
			_refresh_collection_connection_controls()
		return
	if not is_inside_tree() or not _online_mode: return
	if before == _summon_flow.online_state and was_fresh: return
	var selected := str(_online_selected.get("char_id",""))
	var next: Dictionary = _summon_flow.online_state
	if collection_only or before.get("currencies") != next.get("currencies") or before.get("pity") != next.get("pity") or before.get("paidProgress") != next.get("paidProgress") or before.get("paidMilestone") != next.get("paidMilestone") or before.get("paidGuaranteePolicy") != next.get("paidGuaranteePolicy") or before.get("paidTotal") != next.get("paidTotal"):
		_refresh()
	else:
		_update_online_notice()
	var dialog: AcceptDialog = get_node("OnlineRosterDialog")
	if collection_only and not _collection_visible():
		_show_online_roster()
		return
	if not _collection_visible(): return
	if not was_fresh or _roster_card_signature(before) != _roster_card_signature(next):
		_filter_online_roster(_collection_body().get_node("Collection/Search").text)
	else:
		_update_online_party()
	for row in _summon_flow.online_state.get("roster",[]):
		if str(row.char_id) == selected:
			var def: CharacterDef = ContentDB.get_character(selected)
			if def != null: _online_character_details(row,def)
			break

func _roster_card_signature(state: Dictionary) -> Dictionary:
	var cards := {}
	for row in state.get("roster", []):
		cards[str(row.get("char_id",""))] = int(row.get("level",1))
	return {"cards":cards,"party":state.get("party",[])}

func _on_wallet_changed() -> void:
	# The online snapshot, not a local wallet signal, owns affordability.
	# Coalesce notifications instead of rebuilding portrait controls repeatedly.
	if not _summon_busy and is_inside_tree() and _tabs != null:
		_queue_online_refresh()


func _init() -> void:
	screen_title = "Summon"
	screen_subtitle = "Call a new bond into the glade"


func _input(event: InputEvent) -> void:
	# The summon overlay owns Escape even while a tab, button or scroll area has focus.
	if _closing or event.is_echo():
		return
	if event.is_action_pressed("ui_cancel") or event.is_action_pressed("open_menu"):
		if get_node("SummonHistoryDialog").visible:
			get_node("SummonHistoryDialog").hide()
			get_node("SummonHistoryDialog")._invalidate()
		elif _results_layer is SummonRevealOverlay:
			_results_layer.skip_all()
		elif _results_layer != null and is_instance_valid(_results_layer):
			_results_layer.queue_free()
			_results_layer = null
		elif not _summon_busy:
			close_screen()
		var viewport := get_viewport()
		if viewport != null:
			viewport.set_input_as_handled()


func _build_content() -> void:
	var layout := GACHA_LAYOUT_SCENE.instantiate() as VBoxContainer
	layout.size_flags_vertical = Control.SIZE_EXPAND_FILL
	content.add_child(layout)
	if not collection_only and OS.get_name() not in ["Android","iOS","Web"]:
		var shop_button := UIFactory.button("+ BUY MOONSTONES", true)
		shop_button.name = "HeaderMoonstoneShop"
		shop_button.custom_minimum_size = Vector2(185,40)
		shop_button.icon = preload("res://assets/ui/buttons/paid_moonstone.png")
		shop_button.add_theme_constant_override("icon_max_width", 28)
		shop_button.pressed.connect(_open_moonstone_shop)
		header_actions.add_child(shop_button)
		shop_button.visible = not compact_summon_layout()
	_tabs = layout.get_node("BannerTabs") as HFlowContainer
	_main = layout.get_node("Main") as HBoxContainer
	_online_notice = layout.get_node("OfflineNotice/ModeRow/NoticeText")
	_online_switch = layout.get_node("OfflineNotice/ModeRow/OnlineMode")
	_online_roster = layout.get_node("OfflineNotice/ModeRow/OnlineRoster")
	_online_switch.hide()
	_online_roster.pressed.connect(_show_online_roster)
	_pending_recovery = layout.get_node("PendingRecovery")
	_pending_recovery.pressed.connect(_recover_pending_summon)
	if collection_only:
		layout.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
		_embedded_collection_body = get_node("OnlineRosterDialog/BodyScroll") as ScrollContainer
		_embedded_collection_body.reparent(content,false)
		_embedded_collection_body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		_embedded_collection_body.size_flags_vertical = Control.SIZE_EXPAND_FILL
		_embedded_collection_body.hide()
	_collection_retry = layout.get_node("RetryAccountState") as Button
	_collection_retry.pressed.connect(_retry_account_state)
	_history_button = layout.get_node("OfflineNotice/ModeRow/History")
	_history_button.pressed.connect(func():
		if not _summon_busy:
			get_node("SummonHistoryDialog").open_history()
	)


func compact_summon_layout() -> bool:
	var v := get_viewport_rect().size
	return v.x < 900.0 or v.x / maxf(v.y,1.0) < 1.35

func _refresh() -> void:
	if _tabs == null:
		return
	if collection_only:
		_tabs.hide()
		_main.hide()
		_update_online_notice()
		return
	if _selected_banner.is_empty() or not ContentDB.banners.has(_selected_banner):
		var keys := ContentDB.banners.keys()
		_selected_banner = str(keys[0]) if not keys.is_empty() else ""
	UIFactory.clear(_tabs)
	# Keep the exit control and both banner tabs adjacent. An expanding spacer
	# here pushed the tabs beyond the viewport on compact layouts, making the
	# second summon page appear missing or unresponsive.
	var return_button := UIFactory.button("RETURN TO GAME  ✕")
	return_button.name = "ReturnToGameButton"
	return_button.custom_minimum_size = Vector2(120 if compact_summon_layout() else 150, 48)
	return_button.tooltip_text = "Close the summon screen and return to your journey"
	return_button.pressed.connect(close_screen)
	_tabs.add_child(return_button)
	for banner_id in ContentDB.banners.keys():
		var banner: Dictionary = ContentDB.banners[banner_id]
		var button := UIFactory.button(str(banner.get("name", banner_id)), str(banner_id) == _selected_banner)
		button.custom_minimum_size = Vector2(120 if compact_summon_layout() else 160, 48)
		button.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
		button.pressed.connect(func() -> void: _select_banner(str(banner_id)))
		_tabs.add_child(button)
	_update_online_notice()
	_rebuild_main()
	if collection_only:
		_tabs.hide()
		_main.hide()


func _select_banner(banner_id: String) -> void:
	if _summon_busy:
		return
	_selected_banner = banner_id
	_refresh()


func _rebuild_main() -> void:
	_banner_content.rebuild_main()

func _featured_skill_panel(definition: CharacterDef) -> Control:
	return _banner_content.featured_skill_panel(definition)

func _add_scarlet_requiem_banner_template(parent: VBoxContainer, banner: Dictionary, featured_def: CharacterDef, featured_glow: Color) -> void:
	_banner_content.add_scarlet_requiem_banner_template(parent, banner, featured_def, featured_glow)

func _pity_row(title: String, value: int, maximum: int, caption: String, color: Color) -> VBoxContainer:
	return _banner_content.pity_row(title, value, maximum, caption, color)

func _recover_pending_summon() -> void:
	if _summon_busy or not _account_state_ready(): return
	var pending := _summon_flow.pending_online
	if pending.is_empty(): return
	var banner := str(pending.get("bannerId",""))
	var count := int(pending.get("count",0))
	var currency := str(pending.get("currency","crystals"))
	if not ContentDB.banners.has(banner) or count not in [1,10] or currency not in ["crystals","paid_moonstones"]: return
	_select_banner(banner)
	if summon_available(count,1,currency):
		_pull(count,currency == "paid_moonstones")

func _pull(count: int, paid: bool = false) -> void:
	if _summon_busy:
		return
	_summon_busy = true
	_update_online_notice()
	# Lock both pull controls immediately. A second click during the reveal must
	# never spend another batch or race the result overlay.
	for button in _main.find_children("*", "Button", true, false):
		(button as Button).disabled = true
	await _summon_flow.pull(count, paid)
	if not is_instance_valid(self) or not is_inside_tree():
		return
	_summon_busy = false
	_resize_pending = false
	_refresh()

func _play_summon_reveal(results: Array) -> void:
	if _summon_flow != null:
		await _summon_flow.play_summon_reveal(results)

func _show_results(results: Array) -> void:
	if _summon_flow != null:
		_summon_flow.show_results(results)

func presentation_report() -> Dictionary:
	return {
		"screen": "summon",
		"featured_id": _featured_id,
		"featured_premium": _featured_premium,
		"rarity_effects_enabled": true,
		"reveal_animations": _reveal_animations,
		"result_cards": _result_cards,
	}

func _load_default_online() -> void:
	if not is_inside_tree() or not _online_mode or _summon_busy or _summon_flow.online_loading:
		return
	await _toggle_online(true)


func _toggle_online(_value: bool = true) -> void:
	# Compatibility entry point for callers; there is no local summon mode.
	_online_mode = true
	if _summon_busy or not AuthGateway.is_authenticated():
		_refresh()
		return
	_refresh()
	_online_notice.text = "Loading account wallet and collection..."
	var ready := false
	if _summon_flow.online_loading:
		while _summon_flow.online_loading and is_inside_tree():
			await get_tree().process_frame
		ready = _summon_flow.online_state_fresh
	else:
		ready = await _summon_flow.refresh_online_state()
	if not is_inside_tree():
		return
	if not ready:
		EventBus.toast_requested.emit("Account connection unavailable. Reconnect to summon.")
	_refresh()
	if collection_only and not _collection_visible():
		_show_online_roster()
	_refresh_collection_connection_controls()


func summon_currency(kind: String) -> int:
	return int(str(_summon_flow.online_state.get("currencies", {}).get(kind, "0")))

func summon_pity() -> Dictionary:
	return _summon_flow.online_state.get("pity", {}).get(_selected_banner, GachaService.empty_pity())

func _open_moonstone_shop() -> void:
	if _summon_busy or has_node("MoonstoneShop") or OS.get_name() in ["Android","iOS","Web"]: return
	var shop := load("res://scenes/ui/moonstone_shop.tscn").instantiate() as Control
	shop.name = "MoonstoneShop"
	shop.z_index = 90
	add_child(shop)

func paid_guarantee_verified() -> bool:
	return _summon_flow != null and _summon_flow.online_state_fresh and AuthGateway.is_authenticated() and str(_summon_flow.online_state.get("playerId","")) == str(AuthGateway.current_player().get("id","")) and int(_summon_flow.online_state.get("paidMilestone",0)) == 100 and str(_summon_flow.online_state.get("paidGuaranteePolicy","")) == "featured_character_v1" and _summon_flow.online_state.has("paidProgress") and str(_summon_flow.online_state.get("paidTotal","")).is_valid_int()

func paid_summon_progress() -> int:
	return clampi(int(_summon_flow.online_state.get("paidProgress",0)),0,99)


func summon_available(count: int, cost: int, currency: String) -> bool:
	if not AuthGateway.is_authenticated(): return false
	if not _account_state_ready(): return false
	if currency == "paid_moonstones" and not paid_guarantee_verified(): return false
	var pending: Dictionary = _summon_flow.pending_online
	if currency == "paid_moonstones" and OS.has_feature("reverie_public_alpha") and pending.is_empty(): return false
	if not pending.is_empty(): return pending.get("bannerId") == _selected_banner and int(pending.get("count", 0)) == count and str(pending.get("currency","crystals")) == currency
	return summon_currency(currency) >= cost

func _update_online_notice() -> void:
	if _online_notice == null: return
	_online_switch.set_pressed_no_signal(_online_mode)
	_online_switch.disabled = (not AuthGateway.is_authenticated() and not _online_mode) or _summon_busy or _summon_flow.online_loading
	if _pending_recovery != null:
		var recovery := _summon_flow.pending_online
		var paid := str(recovery.get("currency","crystals")) == "paid_moonstones"
		_pending_recovery.visible = not collection_only and AuthGateway.is_authenticated() and not recovery.is_empty()
		_pending_recovery.disabled = _summon_busy or not _account_state_ready() or (paid and not paid_guarantee_verified())
		_pending_recovery.text = "Retry interrupted x%d %s summon" % [int(recovery.get("count",0)), "paid" if paid else "crystal"]
		_pending_recovery.tooltip_text = "Uses the original request. Already processed summons are not charged again; an unprocessed request may spend the original amount."
	_online_roster.visible = not collection_only
	if _history_button != null:
		_history_button.visible = not collection_only
		_history_button.disabled = _summon_busy or not AuthGateway.is_authenticated()
	_online_roster.disabled = not AuthGateway.is_authenticated()
	if is_instance_valid(_collection_retry):
		_collection_retry.visible = AuthGateway.is_authenticated() and not _summon_flow.online_state_fresh
		_collection_retry.disabled = _upgrade_busy or _summon_busy or _summon_flow.online_loading or _summon_flow.online_request_busy
	if not AuthGateway.is_authenticated():
		_online_notice.text = "Sign in to access your account collection and summon."
	elif not _summon_flow.online_state_fresh:
		_online_notice.text = "Reconnecting to your account. Last verified data is read-only; no upgrades or summons until refreshed." if not _summon_flow.online_state.is_empty() else "Account data unavailable. Retry connection; no local currency will be spent."
	else:
		_online_notice.text = "ONLINE: server wallet and collection (%d characters). Mythic summons appear in World Chat." % _summon_flow.online_state.get("roster", []).size()
		if not _summon_flow.pending_online.is_empty():
			_online_notice.text += " Retry pending %d-pull on %s." % [int(_summon_flow.pending_online.get("count", 0)), str(_summon_flow.pending_online.get("bannerId", ""))]

func _retry_account_state() -> void:
	if _upgrade_busy or _summon_busy: return
	await _refresh_live_collection()

func _refresh_collection_connection_controls() -> void:
	if not _collection_visible(): return
	_update_upgrade_controls(_online_selected)
	_refresh_skill_controls()
	_refresh_gear_buttons()
	_update_online_party()
	if not _summon_flow.online_state_fresh:
		_set_upgrade_status("Connection interrupted. Reconnecting; progress shown may be out of date.")
	elif _collection_body().get_node("Collection/UpgradeStatus").text.begins_with("Connection interrupted."):
		_set_upgrade_status("")

func _show_online_roster() -> void:
	var dialog: AcceptDialog = get_node("OnlineRosterDialog")
	_bind_collection_sections()
	var compare_button: Button = _collection_body().get_node("Collection/CompareProgress")
	compare_button.hide()
	var search: LineEdit = _collection_body().get_node("Collection/Search")
	if not search.text_changed.is_connected(_filter_online_roster):
		search.text_changed.connect(_filter_online_roster)
	var buttons := _collection_body().get_node("Collection/UpgradeRow")
	if not buttons.get_node("Ascend").pressed.is_connected(_ascend_selected):
		buttons.get_node("Train").pressed.connect(_train_selected)
		buttons.get_node("Ascend").pressed.connect(_ascend_selected)
		buttons.get_node("Awaken").pressed.connect(_awaken_selected)
	var skill_picker: OptionButton = _collection_body().get_node("Collection/SkillRow/Skill")
	if not skill_picker.item_selected.is_connected(_refresh_skill_controls):
		skill_picker.item_selected.connect(_refresh_skill_controls)
		_collection_body().get_node("Collection/SkillRow/Upgrade").pressed.connect(_upgrade_online_skill)
	var party_bar := _collection_body().get_node("Collection/PartyRow")
	if not party_bar.get_node("PartyToggle").pressed.is_connected(_toggle_online_party_member):
		party_bar.get_node("PartyToggle").pressed.connect(_toggle_online_party_member)
		party_bar.get_node("SaveParty").pressed.connect(_confirm_online_party)
	# Keep team controls above the scrollable cards on small screens.
	var collection := _collection_body().get_node("Collection")
	if party_bar.get_index()>collection.get_node("Search").get_index():collection.move_child(party_bar,collection.get_node("Search").get_index())
	search.clear()
	_filter_online_roster("")
	_set_collection_section("Roster")
	_open_collection_fitted()
	_live_poll_at = Time.get_ticks_msec() + 5000
	_queue_online_refresh()

func _filter_online_roster(query: String) -> void:
	var dialog: AcceptDialog = get_node("OnlineRosterDialog")
	var grid: GridContainer = _collection_body().get_node("Collection/Scroll/Grid")
	for child in grid.get_children():
		grid.remove_child(child)
		child.queue_free()
	var rows: Array = _summon_flow.online_state.get("roster", []).duplicate()
	rows.sort_custom(func(a, b): return str(a.get("char_id", "")) < str(b.get("char_id", "")))
	var filter := query.strip_edges().to_lower()
	var shown := 0
	_online_selected.clear()
	_update_upgrade_picker()
	_update_upgrade_controls({})
	_populate_online_skills({})
	_refresh_online_gear()
	_update_online_party()
	for row in rows:
		var id := str(row.get("char_id", ""))
		var definition: CharacterDef = ContentDB.get_character(id)
		if definition == null: continue
		if not filter.is_empty() and not (definition.display_name + " " + definition.rarity + " " + id).to_lower().contains(filter): continue
		var card: RosterCharacterCard = preload("res://scenes/ui/components/roster_character_card.tscn").instantiate()
		var glow := UITheme.rarity_color(definition.rarity)
		card.setup(id, definition, int(row.get("level", 1)), _summon_flow.online_state.get("party",[]).has(id), UITheme.is_premium_rarity(definition.rarity), glow, UITheme.rarity_tier_label(definition.rarity))
		card.selected.connect(_select_current_online_character)
		grid.add_child(card)
		shown += 1
	_collection_body().get_node("Collection/Summary").text = "%d owned characters  |  %d shown" % [rows.size(), shown]
	_collection_body().get_node("Collection/Detail").text = "Select a character for details. Owned portraits unlock automatically." if shown > 0 else "No characters match your search."

func _update_upgrade_picker() -> void:
	var picker: OptionButton = _collection_body().get_node("Collection/UpgradeCharacter")
	picker.clear()
	picker.add_item("Select owned character")
	picker.set_item_metadata(0,"")
	for row in _summon_flow.online_state.get("roster",[]):
		var id := str(row.get("char_id",""))
		var definition: CharacterDef = ContentDB.get_character(id)
		if definition == null:continue
		picker.add_item("%s | %s | Lv %d" % [definition.display_name,definition.rarity.capitalize(),int(row.get("level",1))])
		picker.set_item_metadata(picker.item_count-1,id)
	picker.disabled = _upgrade_busy or picker.item_count<=1

func _select_upgrade_character(index: int) -> void:
	if _upgrade_busy:return
	var picker: OptionButton = _collection_body().get_node("Collection/UpgradeCharacter")
	var id := str(picker.get_item_metadata(index))
	if id.is_empty():
		_online_selected.clear()
		_update_upgrade_controls({})
		_populate_online_skills({})
		_refresh_online_gear()
		_collection_body().get_node("Collection/Detail").text="Select an owned character."
		return
	for row in _summon_flow.online_state.get("roster",[]):
		if str(row.get("char_id",""))==id:
			var definition: CharacterDef=ContentDB.get_character(id)
			if definition!=null:_online_character_details(row,definition)
			return

func _select_current_online_character(id: String) -> void:
	if _upgrade_busy:return
	for row in _summon_flow.online_state.get("roster",[]):
		if str(row.get("char_id","")) == id:
			var definition: CharacterDef = ContentDB.get_character(id)
			if definition != null:
				_online_character_details(row,definition)
				if _collection_section != "Party": _set_collection_section("Progression")
			return

func _account_state_ready() -> bool:
	return AuthGateway.is_authenticated() and _summon_flow.online_state_fresh and not _summon_flow.online_state.is_empty() and str(_summon_flow.online_state.get("playerId","")) == str(AuthGateway.current_player().get("id","")) and not _summon_flow.online_request_busy and not _summon_flow.online_loading

func _invalidate_account_view(identity_changed: bool = true) -> void:
	_online_selected.clear()
	_set_upgrade_status("")
	if identity_changed:
		_live_refresh_pending = AuthGateway.is_authenticated()
		_live_refresh_at = Time.get_ticks_msec()
		if is_instance_valid(_results_layer):
			if _results_layer is SummonRevealOverlay: _results_layer.skip_all()
			if is_instance_valid(_results_layer):
				_results_layer.hide()
				_results_layer.queue_free()
				_results_layer = null
		AudioDirector.stop_summon_ritual_ambience()
	var dialog: AcceptDialog = get_node("OnlineRosterDialog")
	if _collection_visible():
		_filter_online_roster(_collection_body().get_node("Collection/Search").text)
		_collection_body().get_node("Collection/Detail").text = "Account data unavailable. Reconnecting..." if AuthGateway.is_authenticated() else "Sign in to view your collection."
	_refresh()

func _online_character_details(row: Dictionary, definition: CharacterDef) -> void:
	_online_selected = row.duplicate(true)
	var picker: OptionButton = _collection_body().get_node("Collection/UpgradeCharacter")
	for i in picker.item_count:
		if str(picker.get_item_metadata(i))==str(row.get("char_id","")):picker.select(i);break
	_collection_body().get_node("Collection/Detail").text = "%s  |  %s  |  Level %d  |  Ascension %d  |  Awakening %d  |  Duplicates %d" % [definition.display_name, definition.rarity.capitalize(), int(row.get("level",1)), int(row.get("ascension",0)), int(row.get("awakening",0)), int(row.get("dupes",0))]
	_update_upgrade_controls(row)
	_populate_online_skills(row)
	_refresh_online_gear()
	_update_online_party()
	var level := int(row.get("level",1))
	var cap := 20*(int(row.get("ascension",0))+1)
	var progress_text := "Level cap reached" if level >= cap else "%d / %d XP" % [int(str(row.get("xp","0"))),100+(level-1)*85]
	_collection_body().get_node("Collection/Detail").text += " | " + progress_text

func close_screen() -> void:
	if _summon_busy or _upgrade_busy or (_summon_flow != null and _summon_flow.online_loading): return
	super.close_screen()

func _update_upgrade_controls(row: Dictionary) -> void:
	var buttons := _collection_body().get_node("Collection/UpgradeRow")
	var ascend: Button = buttons.get_node("Ascend")
	var awaken: Button = buttons.get_node("Awaken")
	var tier := int(row.get("ascension", 0))
	var awakening := int(row.get("awakening", 0))
	var gold := 800 * (tier + 1)
	var dew := tier + 1
	var cap := 20 * (tier + 1)
	var inventory: Dictionary = _summon_flow.online_state.get("inventory", {})
	var gold_ready := summon_currency("gold") >= gold
	var dew_ready := int(str(inventory.get("dew_of_awakening", "0"))) >= dew
	ascend.text = "Ascend: %d gold + %d dew" % [gold, dew] if tier < 3 else "Max ascension"
	ascend.disabled = row.is_empty() or _upgrade_busy or tier >= 3 or int(row.get("level", 0)) != cap or not gold_ready or not dew_ready
	ascend.tooltip_text = "Requires level %d and the displayed materials." % cap
	var root := _collection_body().get_node("Collection")
	root.get_node("UpgradeCharacter").disabled = _upgrade_busy or root.get_node("UpgradeCharacter").item_count<=1
	var hint: Label = root.get_node("UpgradeHint")
	if row.is_empty():
		hint.text = "Select an owned character above."
	else:
		hint.text = "Level %d / %d | Ascension %d/3 | Awakening %d/5" % [int(row.get("level",1)),cap,tier,awakening]
		if tier<3:
			hint.text += "\nAscend: reach Lv %d; gold %d/%d; Dew of Awakening %d/%d." % [cap,summon_currency("gold"),gold,int(str(inventory.get("dew_of_awakening","0"))),dew]
			if int(row.get("level",1))<cap:hint.text += " Earn XP in battles."
		else:hint.text += "\nMaximum ascension reached."
		hint.text += "\nAwakening: %d/2 duplicates." % int(row.get("dupes",0))
		var fusion=preload("res://scripts/gacha/character_upgrade_card.gd")
		var recipe: Dictionary=fusion.ascension_recipe(str(row.get("char_id","")))
		if not recipe.is_empty():
			hint.text += "\nMythic acquisitions: %d/%d (automatically fully ascends)." % [int(str(inventory.get(str(recipe.item),"0"))),int(recipe.cost)]
		var mythic: Dictionary=fusion.mythic_recipe(str(row.get("char_id","")))
		if not mythic.is_empty():
			var mythic_target := ContentDB.get_character(str(mythic.target))
			var mythic_name := mythic_target.display_name if mythic_target != null else str(mythic.target)
			hint.text += "\nLegendary copies: %d/%d toward %s. Fuses automatically; your Legendary stays playable and keeps its upgrades." % [int(str(inventory.get(str(mythic.item),"0"))),int(mythic.cost),mythic_name]
	var ready := _account_state_ready()
	ascend.disabled = ascend.disabled or not ready
	var train: Button = buttons.get_node("Train")
	var level := int(row.get("level",1))
	var cost := maxi(1,100+(level-1)*85-int(str(row.get("xp","0"))))
	train.text = "Level up: %d gold" % cost if level<cap else ("Maximum level reached" if tier>=3 else "Level cap - ascend first")
	train.disabled = row.is_empty() or _upgrade_busy or not ready or level>=cap or summon_currency("gold")<cost
	if not row.is_empty():
		hint.text += "\nTraining: %d/%d gold for next level. Battle XP reduces the cost." % [summon_currency("gold"),cost] if level<cap else ("\nMaximum level reached (80)." if tier>=3 else "\nAscend to unlock more levels.")
	awaken.text = "Awaken: 2 duplicates" if awakening < 5 else "Max awakening"
	awaken.disabled = row.is_empty() or _upgrade_busy or awakening >= 5 or int(row.get("dupes",0)) < 2 or not ready
	_refresh_skill_controls()

func _set_upgrade_status(message: String) -> void:
	_collection_body().get_node("Collection/UpgradeStatus").text=message

func _wait_upgrade_connection(owner: String,generation: int) -> bool:
	var deadline:=Time.get_ticks_msec()+15000
	while true:
		if not is_inside_tree() or owner!=str(AuthGateway.current_player().get("id","")) or generation!=_summon_flow.session_generation:return false
		if _account_state_ready() and AuthGateway.access_token_ready_for_connection():return true
		if not _summon_flow.online_loading and not _summon_flow.online_request_busy and AuthGateway.access_token_ready_for_connection():
			await _summon_flow.refresh_online_state()
			if owner!=str(AuthGateway.current_player().get("id","")) or generation!=_summon_flow.session_generation:return false
			if _account_state_ready():return true
			await get_tree().create_timer(0.5).timeout
		if Time.get_ticks_msec()>deadline:return false
		await get_tree().process_frame
	return false

func _upgrade_connection_failed(row: Dictionary,owner: String,generation: int) -> void:
	_upgrade_busy=false
	if owner!=str(AuthGateway.current_player().get("id","")) or generation!=_summon_flow.session_generation:return
	_update_upgrade_controls(_online_selected)
	_set_upgrade_status("Connection unavailable. Reopen collection or retry.")
	EventBus.toast_requested.emit("Upgrade connection unavailable.")

func _upgrade_online_character(action: String) -> void:
	if _upgrade_busy or not _online_mode or _online_selected.is_empty(): return
	var button: Button = _collection_body().get_node("Collection/UpgradeRow/"+("Ascend" if action=="ascend" else "Awaken"))
	if button.disabled:return
	var row: Dictionary = _online_selected.duplicate(true)
	_upgrade_busy = true
	_update_upgrade_controls(row)
	var identity := str(AuthGateway.current_player().get("id", ""))
	var generation := _summon_flow.session_generation
	var tier := int(row.get("ascension" if action == "ascend" else "awakening",0))
	_set_upgrade_status("Saving upgrade to server...")
	if not await _wait_upgrade_connection(identity,generation):
		_upgrade_connection_failed(row,identity,generation)
		return
	var result := await _summon_flow._online_call("/upgrade", {"characterId": str(row.char_id), "action":action, "expectedTier":tier})
	if generation != _summon_flow.session_generation or identity != str(AuthGateway.current_player().get("id","")):
		_upgrade_busy = false
		return
	var refreshed := await _summon_flow.refresh_online_state()
	AuthGateway.refresh_online_wallet()
	_upgrade_busy = false
	var query: String = _collection_body().get_node("Collection/Search").text
	_filter_online_roster(query)
	for updated in _summon_flow.online_state.get("roster", []):
		if str(updated.char_id) == str(row.char_id):
			var definition: CharacterDef = ContentDB.get_character(str(updated.char_id))
			if definition != null: _online_character_details(updated, definition)
			break
	_refresh()
	_set_upgrade_status(("Saved to your account." if refreshed else "Server confirmed. Reconnect to refresh balances.") if bool(result.get("ok",false)) else str(result.get("error","Upgrade interrupted. Retry after refreshing.")).replace("_"," "))
	if bool(result.get("ok",false)):
		EventBus.toast_requested.emit("Character upgraded.")
	else:
		EventBus.toast_requested.emit(str(result.get("error","Upgrade interrupted. Refresh collection.")).replace("_"," "))

func _train_selected() -> void:
	if _upgrade_busy or _online_selected.is_empty() or _collection_body().get_node("Collection/UpgradeRow/Train").disabled:return
	var row := _online_selected.duplicate(true)
	var owner := str(AuthGateway.current_player().get("id",""))
	var generation := _summon_flow.session_generation
	_upgrade_busy=true
	_update_upgrade_controls(row)
	_set_upgrade_status("Training character...")
	if not await _wait_upgrade_connection(owner,generation):
		_upgrade_connection_failed(row,owner,generation)
		return
	var result := await _summon_flow._online_call("/train",{"characterId":str(row.char_id),"expectedLevel":int(row.level),"expectedXp":int(str(row.get("xp","0")))})
	if generation!=_summon_flow.session_generation or owner!=str(AuthGateway.current_player().get("id","")):
		_upgrade_busy=false
		return
	var refreshed := await _summon_flow.refresh_online_state()
	AuthGateway.refresh_online_wallet()
	_upgrade_busy=false
	_filter_online_roster(_collection_body().get_node("Collection/Search").text)
	_select_upgrade_character_by_id(str(row.char_id))
	_refresh()
	_set_upgrade_status(("Level increased. Saved to your account." if refreshed else "Training saved. Refresh to view the new level.") if bool(result.get("ok",false)) else str(result.get("error","Training interrupted. Refresh collection.")).replace("_"," "))

func _select_upgrade_character_by_id(id: String) -> void:
	for updated in _summon_flow.online_state.get("roster",[]):
		if str(updated.char_id)==id:
			var definition: CharacterDef=ContentDB.get_character(id)
			if definition!=null:_online_character_details(updated,definition)
			return

func _ascend_selected() -> void:
	await _upgrade_online_character("ascend")

func _awaken_selected() -> void:
	await _upgrade_online_character("awaken")

func _populate_online_skills(row: Dictionary) -> void:
	var picker: OptionButton = _collection_body().get_node("Collection/SkillRow/Skill")
	var previous := str(picker.get_selected_metadata()) if picker.selected >= 0 else ""
	picker.clear()
	var definition: CharacterDef = ContentDB.get_character(str(row.get("char_id", "")))
	if definition != null:
		var ids: Array = definition.skills.duplicate()
		if not definition.ultimate.is_empty() and not ids.has(definition.ultimate): ids.append(definition.ultimate)
		for id in ids:
			var skill: SkillDef = ContentDB.get_skill(str(id))
			if skill == null or skill.kind not in ["damage","heal","shield","buff","debuff"]: continue
			var lv := int(row.get("skill_levels", {}).get(str(id), 1))
			picker.add_item("%s | Lv. %d" % [skill.display_name,lv])
			picker.set_item_metadata(picker.item_count-1, str(id))
			if previous == str(id): picker.select(picker.item_count-1)
	picker.disabled = picker.item_count == 0 or _upgrade_busy
	_refresh_skill_controls()

func _refresh_skill_controls(_index: int = -1) -> void:
	var picker: OptionButton = _collection_body().get_node("Collection/SkillRow/Skill")
	var button: Button = _collection_body().get_node("Collection/SkillRow/Upgrade")
	var hint: Label = _collection_body().get_node("Collection/SkillHint")
	button.disabled = true
	button.text = "Upgrade skill"
	hint.text = "Select a character to see their skills."
	if _online_selected.is_empty() or picker.selected < 0: return
	var id := str(picker.get_selected_metadata())
	var skill: SkillDef = ContentDB.get_skill(id)
	if skill == null: return
	var lv := int(_online_selected.get("skill_levels", {}).get(id, 1))
	if lv >= 5:
		hint.text = "Maximum skill level reached."
		return
	var gold := (150 if skill.ultimate else 100) * lv
	var petals := int(str(_summon_flow.online_state.get("inventory", {}).get("moonpetal", "0")))
	button.text = "Upgrade to Lv. %d" % (lv+1)
	hint.text = "Requires Lv. %d | %d gold | %d Moonpetal (owned: %d)" % [lv*5,gold,lv,petals]
	button.disabled = _upgrade_busy or not _online_mode or not _account_state_ready() or int(_online_selected.get("level",0)) < lv*5 or summon_currency("gold") < gold or petals < lv

func _upgrade_online_skill() -> void:
	if _upgrade_busy or not _online_mode or _online_selected.is_empty(): return
	var picker: OptionButton = _collection_body().get_node("Collection/SkillRow/Skill")
	if picker.selected < 0 or _collection_body().get_node("Collection/SkillRow/Upgrade").disabled: return
	var row := _online_selected.duplicate(true)
	var id := str(picker.get_selected_metadata())
	var lv := int(row.get("skill_levels", {}).get(id,1))
	var owner := str(AuthGateway.current_player().get("id",""))
	var generation := _summon_flow.session_generation
	_upgrade_busy = true
	_update_upgrade_controls(row)
	_refresh_skill_controls()
	_set_upgrade_status("Saving upgrade to server...")
	if not await _wait_upgrade_connection(owner,generation):
		_upgrade_connection_failed(row,owner,generation)
		return
	var result := await _summon_flow._online_call("/skill-upgrade", {"characterId":str(row.char_id),"skillId":id,"expectedLevel":lv})
	if generation != _summon_flow.session_generation or owner != str(AuthGateway.current_player().get("id","")):
		_upgrade_busy = false
		return
	var refreshed := await _summon_flow.refresh_online_state()
	AuthGateway.refresh_online_wallet()
	_upgrade_busy = false
	_filter_online_roster(_collection_body().get_node("Collection/Search").text)
	for updated in _summon_flow.online_state.get("roster",[]):
		if str(updated.char_id) == str(row.char_id):
			var definition: CharacterDef = ContentDB.get_character(str(updated.char_id))
			if definition != null: _online_character_details(updated, definition)
			for i in range(picker.item_count):
				if str(picker.get_item_metadata(i)) == id: picker.select(i)
			_refresh_skill_controls()
			break
	_refresh()
	_set_upgrade_status(("Saved to your account." if refreshed else "Server confirmed. Reconnect to refresh balances.") if bool(result.get("ok",false)) else str(result.get("error","Upgrade interrupted. Retry after refreshing.")).replace("_"," "))
	EventBus.toast_requested.emit("Skill upgraded." if bool(result.get("ok",false)) else str(result.get("error","Upgrade interrupted. Refresh collection.")).replace("_"," "))

func _bind_online_gear() -> void:
	var bar := _collection_body().get_node("Collection/GearRow")
	var slot: OptionButton = bar.get_node("Slot")
	if slot.item_count != 0: return
	for id in ["weapon","armor","accessory"]:
		slot.add_item(id.capitalize())
		slot.set_item_metadata(slot.item_count-1,id)
	slot.select(0)
	slot.item_selected.connect(func(_i): _refresh_online_gear())
	bar.get_node("Item").item_selected.connect(func(_i): _refresh_gear_buttons())
	bar.get_node("Equip").pressed.connect(func(): await _online_gear_action("equip"))
	bar.get_node("Remove").pressed.connect(func(): await _online_gear_action("unequip"))
	bar.get_node("Enhance").pressed.connect(func(): await _online_gear_action("enhance"))
	bar.get_node("Reroll").pressed.connect(func(): await _online_gear_action("reroll"))

func _current_online_gear() -> Dictionary:
	var slot: OptionButton = _collection_body().get_node("Collection/GearRow/Slot")
	for gear in _online_selected.get("equipment",[]):
		if gear.slot == slot.get_selected_metadata(): return gear
	return {}

func _refresh_online_gear() -> void:
	_bind_online_gear()
	var bar := _collection_body().get_node("Collection/GearRow")
	var slot: OptionButton = bar.get_node("Slot")
	var picker: OptionButton = bar.get_node("Item")
	var prev := str(picker.get_selected_metadata()) if picker.selected >= 0 else ""
	picker.clear()
	var inventory: Dictionary = _summon_flow.online_state.get("inventory",{})
	var current := _current_online_gear()
	if not _online_selected.is_empty():
		for id in inventory:
			var def: Dictionary = ContentDB.get_item(str(id))
			if def.get("category") != "equipment" or def.get("slot") != slot.get_selected_metadata() or id == current.get("item_id",""): continue
			picker.add_item("%s x%s" % [def.get("name",id),inventory[id]])
			picker.set_item_metadata(picker.item_count-1,id)
			if prev == str(id): picker.select(picker.item_count-1)
	if picker.item_count > 0 and picker.selected < 0: picker.select(0)
	picker.disabled = picker.item_count == 0 or _upgrade_busy
	_refresh_gear_buttons()

func _refresh_gear_buttons() -> void:
	var bar := _collection_body().get_node("Collection/GearRow")
	var picker: OptionButton = bar.get_node("Item")
	var current := _current_online_gear()
	var locked := _upgrade_busy or not _online_mode or not _account_state_ready() or _online_selected.is_empty()
	bar.get_node("Equip").disabled = locked or picker.selected < 0
	bar.get_node("Remove").disabled = locked or current.is_empty()
	var lv := int(current.get("enhancement_level",0))
	var def: Dictionary = ContentDB.get_item(str(current.get("item_id","")))
	var cap := int(GameState.roster_domain.GEAR_RARITY_CAPS.get(def.get("rarity","common"),5))
	var inventory: Dictionary = _summon_flow.online_state.get("inventory",{})
	var gold := 180*(lv+1)
	var sap := lv+1
	var shards := maxi(0,lv-4)
	bar.get_node("Enhance").disabled = locked or current.is_empty() or lv>=cap or summon_currency("gold")<gold or int(str(inventory.get("glade_sap","0")))<sap or int(str(inventory.get("gothic_shard","0")))<shards
	var can_roll := false
	var stats: Dictionary = def.get("stats", {})
	for stat in ["hp","atk","def","spd","crit","crit_dmg"]:
		if float(stats.get(stat,0)) > 0: can_roll = true
	bar.get_node("Reroll").disabled = locked or current.is_empty() or not can_roll or summon_currency("gold") < 120 or int(str(inventory.get("gothic_shard","0"))) < 1
	bar.get_node("Reroll").tooltip_text = "120 gold + 1 Gothic Shard; replaces the current bonus."
	var hint: Label = _collection_body().get_node("Collection/GearHint")
	hint.text = "Equipped: %s +%d / +%d | Next: %d gold, %d sap, %d shards" % [def.get("name","None"),lv,cap,gold,sap,shards] if not current.is_empty() else "Empty slot. Select equipment from your online inventory."
	if not current.is_empty():
		var stat := str(current.get("reroll_stat","")) if current.get("reroll_stat") != null else ""
		var value := float(str(current.get("reroll_value","0"))) if not stat.is_empty() else 0.0
		hint.text += "\nBonus: %s | Reroll: 120 gold + 1 Gothic Shard" % (("%s +%s" % [stat.to_upper(),str(value)]) if not stat.is_empty() else "None")

func _online_gear_action(action: String) -> void:
	if _upgrade_busy or not _online_mode or _online_selected.is_empty(): return
	var bar := _collection_body().get_node("Collection/GearRow")
	var control: String = {"equip":"Equip","unequip":"Remove","enhance":"Enhance","reroll":"Reroll"}.get(action,"")
	if control == "" or bar.get_node(control).disabled: return
	var row := _online_selected.duplicate(true)
	var current := _current_online_gear()
	var slot: OptionButton = bar.get_node("Slot")
	var picker: OptionButton = bar.get_node("Item")
	var body := {"characterId":str(row.char_id),"slot":str(slot.get_selected_metadata()),"action":action,"itemId":str(picker.get_selected_metadata()) if action=="equip" else "","expectedItem":str(current.get("item_id","")),"expectedLevel":int(current.get("enhancement_level",0)),"requestId":_summon_flow._uuid()}
	if action == "reroll":
		body["expectedRerollStat"] = str(current.get("reroll_stat","")) if current.get("reroll_stat") != null else ""
		body["expectedRerollValue"] = float(str(current.get("reroll_value","0"))) if current.get("reroll_value") != null else 0.0
	var owner := str(AuthGateway.current_player().get("id",""))
	var generation := _summon_flow.session_generation
	_upgrade_busy = true
	_update_upgrade_controls(row)
	_refresh_gear_buttons()
	_set_upgrade_status("Saving upgrade to server...")
	if not await _wait_upgrade_connection(owner,generation):
		_upgrade_connection_failed(row,owner,generation)
		return
	var result := await _summon_flow._online_call("/equipment",body)
	if generation != _summon_flow.session_generation or owner != str(AuthGateway.current_player().get("id","")):
		_upgrade_busy = false
		return
	var refreshed := await _summon_flow.refresh_online_state()
	AuthGateway.refresh_online_wallet()
	_upgrade_busy = false
	_filter_online_roster(_collection_body().get_node("Collection/Search").text)
	for updated in _summon_flow.online_state.get("roster",[]):
		if str(updated.char_id) == str(row.char_id):
			var definition: CharacterDef = ContentDB.get_character(str(updated.char_id))
			if definition != null: _online_character_details(updated,definition)
			break
	_refresh()
	_set_upgrade_status(("Saved to your account." if refreshed else "Server confirmed. Reconnect to refresh balances.") if bool(result.get("ok",false)) else str(result.get("error","Upgrade interrupted. Retry after refreshing.")).replace("_"," "))
	EventBus.toast_requested.emit("Equipment updated." if bool(result.get("ok",false)) else str(result.get("error","Equipment request interrupted. Refresh collection.")).replace("_"," "))

func _update_online_party() -> void:
	var bar := _collection_body().get_node("Collection/PartyRow")
	var members: Array = _summon_flow.online_state.get("party",[])
	var labels: PackedStringArray = []
	for id in members:
		var def: CharacterDef = ContentDB.get_character(str(id))
		labels.append(def.display_name if def != null else str(id))
	bar.get_node("PartySummary").text = "Party %d/4: %s" % [members.size(),", ".join(labels)]
	var toggle: Button = bar.get_node("PartyToggle")
	var selected := str(_online_selected.get("char_id",""))
	var included := members.has(selected)
	var replacement: OptionButton = bar.get_node("ReplaceSlot")
	var prior := str(replacement.get_selected_metadata()) if replacement.selected>=0 else ""
	replacement.clear()
	var full := not included and members.size()>=4 and not selected.is_empty()
	replacement.visible = full
	if full:
		for id in members:
			var def: CharacterDef = ContentDB.get_character(str(id))
			replacement.add_item("Replace "+(def.display_name if def!=null else str(id)))
			replacement.set_item_metadata(replacement.item_count-1,id)
			if str(id)==prior:replacement.select(replacement.item_count-1)
	toggle.text = "Remove from party" if included else ("Replace member" if full else "Deploy character")
	var expedition_locked := bool(_summon_flow.online_state.get("partyLocked",false))
	if expedition_locked: bar.get_node("PartySummary").text += " | Expedition locked"
	var ready := _account_state_ready()
	toggle.disabled = expedition_locked or _upgrade_busy or selected.is_empty() or (included and members.size()<=1) or not _online_mode or not ready
	replacement.disabled = toggle.disabled
	if selected.is_empty():bar.get_node("PartySummary").text += " | Tap an owned character below"
	if GameState.roster_domain.story_solo_active():bar.get_node("PartySummary").text += " | Kael-only story segment; saved team applies after it."
	if expedition_locked:bar.get_node("PartySummary").text += " | Leave the current expedition or PvP match to edit"
	bar.get_node("SaveParty").disabled = expedition_locked or _upgrade_busy or members.is_empty() or not _online_mode or not ready

func _change_online_party(toggle: bool) -> void:
	if _upgrade_busy or not _online_mode: return
	var initial_owner := str(AuthGateway.current_player().get("id",""))
	var initial_generation := _summon_flow.session_generation
	var requested_character := str(_online_selected.get("char_id",""))
	var replacement_picker: OptionButton = _collection_body().get_node("Collection/PartyRow/ReplaceSlot")
	var requested_replacement := str(replacement_picker.get_selected_metadata()) if replacement_picker.selected>=0 else ""
	if initial_owner.is_empty():return
	_upgrade_busy=true
	_update_online_party()
	# Wait for an in-flight read or credential refresh, rather than losing a tap.
	var deadline:=Time.get_ticks_msec()+15000
	while not _account_state_ready() or not AuthGateway.access_token_ready_for_connection():
		if not is_inside_tree() or initial_generation!=_summon_flow.session_generation or initial_owner!=str(AuthGateway.current_player().get("id","")) or Time.get_ticks_msec()>deadline:
			_upgrade_busy=false
			_update_online_party()
			EventBus.toast_requested.emit("Team connection unavailable. Try again.")
			return
		await get_tree().process_frame
	if bool(_summon_flow.online_state.get("partyLocked",false)):
		_upgrade_busy=false
		_update_online_party()
		EventBus.toast_requested.emit("Leave your current expedition or PvP match to edit your team.")
		return
	_upgrade_busy=false
	var ids: Array = _summon_flow.online_state.get("party",[]).duplicate()
	var selected := requested_character
	if toggle:
		if selected.is_empty(): return
		if ids.has(selected):
			if ids.size()<=1: return
			ids.erase(selected)
		else:
			if ids.size()>=4:
				var slot:=ids.find(requested_replacement)
				if slot<0:
					_update_online_party()
					EventBus.toast_requested.emit("The team changed. Select a replacement slot again.")
					return
				ids[slot]=selected
			else:ids.append(selected)
	if ids.is_empty(): return
	var owner := str(AuthGateway.current_player().get("id",""))
	var generation := _summon_flow.session_generation
	_upgrade_busy = true
	_update_online_party()
	var result := await _summon_flow._online_call("/party",{"characterIds":ids})
	if generation != _summon_flow.session_generation or owner != str(AuthGateway.current_player().get("id","")):
		_upgrade_busy = false
		return
	await _summon_flow.refresh_online_state()
	if bool(result.get("ok",false)):
		await AuthGateway.refresh_account_roster()
	_upgrade_busy = false
	_filter_online_roster(_collection_body().get_node("Collection/Search").text)
	for updated in _summon_flow.online_state.get("roster",[]):
		if str(updated.char_id) == selected:
			var def: CharacterDef = ContentDB.get_character(selected)
			if def != null: _online_character_details(updated,def)
			break
	_refresh()
	EventBus.toast_requested.emit("Online party saved." if bool(result.get("ok",false)) else str(result.get("error","Party update failed.")).replace("_"," "))

func _toggle_online_party_member() -> void:
	await _change_online_party(true)

func _confirm_online_party() -> void:
	await _change_online_party(false)

func _show_progress_comparison() -> void:
	if _upgrade_busy or _summon_busy or not _online_mode or not AuthGateway.is_authenticated(): return
	var owner := str(AuthGateway.current_player().get("id",""))
	if owner.is_empty() or owner != GameState.lifecycle_component.active_player_id: return
	if _summon_flow.online_loading: return
	_upgrade_busy = true
	var success := await _summon_flow.refresh_online_state()
	_upgrade_busy = false
	if not success or owner != str(AuthGateway.current_player().get("id","")) or owner != GameState.lifecycle_component.active_player_id:
		EventBus.toast_requested.emit("Online comparison unavailable. No progress was changed.")
		return
	var comparison = preload("res://scripts/ui/components/progress_comparison.gd")
	var report: Dictionary = comparison.compare(GameState._to_dict(), _summon_flow.online_state)
	var dialog: AcceptDialog = get_node("OnlineRosterDialog/ProgressComparison")
	dialog.get_node("Content/Scroll/Report").text = comparison.format_report(report)
	dialog.popup_centered(Vector2i(700,520))

func _clear_progress_comparison(_signed_in: bool, _player: Dictionary) -> void:
	var dialog: AcceptDialog = get_node_or_null("OnlineRosterDialog/ProgressComparison")
	if dialog != null:
		dialog.hide()
		dialog.get_node("Content/Scroll/Report").text = ""

var _collection_section := "Roster"

func _bind_collection_sections() -> void:
	var dialog: AcceptDialog = get_node("OnlineRosterDialog")
	var tabs := _collection_body().get_node("Collection/SectionTabs")
	if not tabs.get_node("Roster").pressed.is_connected(_show_roster_section):
		tabs.get_node("Roster").pressed.connect(_show_roster_section)
		tabs.get_node("Progression").pressed.connect(func(): _set_collection_section("Progression"))
		tabs.get_node("Equipment").pressed.connect(func(): _set_collection_section("Equipment"))
		_collection_body().get_node("Collection/UpgradeCharacter").item_selected.connect(_select_upgrade_character)
		tabs.get_node("Party").pressed.connect(func(): _set_collection_section("Party"))
		dialog.size_changed.connect(_resize_collection_grid)
		_collection_body().resized.connect(_resize_collection_grid)
		_collection_body().get_node("Collection/Scroll").resized.connect(_resize_collection_grid)

func _show_roster_section() -> void:
	_set_collection_section("Roster")

func _set_collection_section(section: String) -> void:
	var root := _collection_body().get_node("Collection")
	_collection_section = section
	_collection_body().scroll_vertical = 0
	for id in ["Roster","Progression","Equipment","Party"]:
		root.get_node("SectionTabs/"+id).set_pressed_no_signal(id==section)
	for id in ["Search","Scroll"]:
		root.get_node(id).visible = section=="Roster" or section=="Party"
	for id in ["UpgradeRow","UpgradeHint","UpgradeStatus","SkillRow","SkillHint"]:
		root.get_node(id).visible = section=="Progression"
	root.get_node("UpgradeCharacter").visible=section=="Progression" or section=="Equipment"
	for id in ["GearRow","GearHint"]:
		root.get_node(id).visible = section=="Equipment"
	root.get_node("PartyRow").visible = section=="Party"
	if section=="Party":
		_update_online_party()
	_resize_collection_grid.call_deferred()

func _resize_collection_grid() -> void:
	var dialog: AcceptDialog = get_node("OnlineRosterDialog")
	var scroll: ScrollContainer = _collection_body().get_node("Collection/Scroll")
	var grid: GridContainer = scroll.get_node("Grid")
	if scroll.size.x > 0:
		grid.columns = clampi(int((scroll.size.x-16.0)/148.0),1,6)

func _open_collection_fitted() -> void:
	var dialog: AcceptDialog = get_node("OnlineRosterDialog")
	var viewport_size := Vector2i(get_viewport_rect().size)
	var target := Vector2i(clampi(viewport_size.x-32,280,960),clampi(viewport_size.y-48,200,620))
	if collection_only:
		_collection_open = true
		_collection_body().show()
	else:
		dialog.popup_centered(target)
	_resize_collection_grid.call_deferred()
