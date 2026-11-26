class_name GachaSummonFlowComponent
extends Control
## Owns pull requests, summon reveal timing and the results-card presentation.

var screen: GachaScreen


func bind(owner_screen: GachaScreen) -> void:
	screen = owner_screen
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	online_bind()


func pull(count: int, paid: bool = false) -> void:
	if not is_instance_valid(screen) or screen._summon_busy == false:
		return
	if not AuthGateway.is_authenticated():
		EventBus.toast_requested.emit("Sign in to summon.")
		return
	var banner_id := screen._selected_banner
	var currency_id := "paid_moonstones" if paid else "crystals"
	var generation := session_generation
	var result: Dictionary = await pull_online(banner_id, count, currency_id)
	if generation != session_generation: return
	if not bool(result.get("ok", false)):
		EventBus.toast_requested.emit(str(result.get("error", "Summon failed.")))
		return
	var rolls: Array = result.get("results", [])
	await play_summon_reveal(rolls)
	if generation != session_generation or not is_instance_valid(screen) or not screen.is_inside_tree():
		return
	show_results(rolls, currency_id, banner_id)


func play_summon_reveal(results: Array) -> void:
	if screen._results_layer != null and is_instance_valid(screen._results_layer):
		screen._results_layer.queue_free()
	screen._results_layer = GachaScreen.SUMMON_REVEAL_SCENE.instantiate() as Control
	screen.add_child(screen._results_layer)
	var reveal := screen._results_layer as SummonRevealOverlay
	AudioDirector.play_summon_ritual_ambience()
	await reveal.play_batch(results)
	if not is_instance_valid(screen) or not screen.is_inside_tree():
		return
	AudioDirector.stop_summon_ritual_ambience()
	if is_instance_valid(screen._results_layer):
		screen._results_layer.hide()
		screen._results_layer.queue_free()
	screen._results_layer = null


# Resize existing cards in place. Do not replay animations or reconstruct actions.
func resize_results() -> void:
	if not is_instance_valid(screen) or not is_instance_valid(screen._results_layer) or screen._results_layer is SummonRevealOverlay:
		return
	var layer := screen._results_layer
	var panel := layer.get_node_or_null("Center/Panel") as PanelContainer
	if panel == null: return
	var dimensions := screen.get_viewport_rect().size
	var narrow := dimensions.x < 600.0
	var panel_width := clampf(dimensions.x - (24.0 if screen.compact_summon_layout() else 48.0),250.0,1120.0)
	panel.custom_minimum_size = Vector2(panel_width,0)
	var header := panel.get_node("Content/Header") as BoxContainer
	header.vertical = narrow
	header.get_node("HeaderSpacer").visible = not narrow
	header.get_node("Title").add_theme_font_size_override("font_size",20 if narrow else 24)
	var grid := panel.get_node("Content/ResultsScroll/ResultGrid") as GridContainer
	var columns := 2 if panel_width < 520.0 else (3 if panel_width < 760.0 else (4 if panel_width < 960.0 else 5))
	grid.columns = mini(columns,maxi(1,grid.get_child_count()))
	var scroll := grid.get_parent() as ScrollContainer
	scroll.custom_minimum_size.y = maxf(100.0,minf(dimensions.y - (330.0 if narrow else 210.0),590.0 if grid.get_child_count()>grid.columns else 310.0))
	var card_width := clampf((panel_width-40.0-float(grid.columns-1)*12.0)/float(grid.columns),118.0,200.0)
	for card in grid.get_children():
		card.custom_minimum_size = Vector2(card_width,286.0)
		card.pivot_offset = card.custom_minimum_size * 0.5
		var portrait := card.get_node("Content/Portrait") as PortraitView
		var portrait_width := minf(132.0,card_width-16.0)
		portrait.custom_minimum_size = Vector2(portrait_width,portrait_width*1.5)
	var footer := panel.get_node("Content/Footer") as BoxContainer
	footer.vertical = narrow
	footer.get_node("Message").visible = not narrow
	panel.reset_size()

func show_results(results: Array, currency_id: String = "crystals", banner_id: String = "") -> void:
	if banner_id.is_empty():
		banner_id = screen._selected_banner
	screen._reveal_animations = 0
	screen._result_cards = results.size()
	if screen._results_layer != null and is_instance_valid(screen._results_layer):
		screen._results_layer.queue_free()
	screen._results_layer = GachaScreen.SUMMON_RESULTS_SCENE.instantiate() as Control
	screen.add_child(screen._results_layer)
	screen._results_layer.z_index = 80

	var panel := screen._results_layer.get_node("Center/Panel") as PanelContainer
	var viewport_width := screen.get_viewport_rect().size.x
	var compact := screen.compact_summon_layout()
	var narrow := viewport_width < 600.0
	var panel_width := clampf(viewport_width - (24.0 if compact else 48.0), 250.0, 1120.0)
	var header := screen._results_layer.get_node("Center/Panel/Content/Header") as BoxContainer
	header.vertical = narrow
	if narrow:
		header.get_node("HeaderSpacer").hide()
		header.get_node("Title").add_theme_font_size_override("font_size",20)
	panel.custom_minimum_size = Vector2(panel_width, 0.0)
	panel.add_theme_stylebox_override(
		"panel",
		UITheme.style(Color("#0b1120"), Color(UITheme.GOLD.r, UITheme.GOLD.g, UITheme.GOLD.b, 0.45), 16, 1, 20, true)
	)
	var header_chip_slot := screen._results_layer.get_node("Center/Panel/Content/Header/BestChipSlot") as HBoxContainer
	var best_rank := -1
	for roll in results:
		best_rank = maxi(best_rank, int(GachaService.RARITY_RANK.get(str(roll.get("rarity", "common")), 0)))
	var best_name := "Common"
	for rarity in GachaService.RARITY_ORDER:
		if int(GachaService.RARITY_RANK.get(rarity, 0)) == best_rank:
			best_name = rarity.capitalize()
	header_chip_slot.add_child(UIFactory.chip("Best: " + best_name, UITheme.rarity_color(best_name.to_lower())))
	if UITheme.is_premium_rarity(best_name.to_lower()):
		var best_effect := UITheme.rarity_effect(best_name.to_lower())
		var best_glow: Color = best_effect.get("glow", UITheme.GOLD_BRIGHT)
		header_chip_slot.add_child(UIFactory.label("✦ " + UITheme.rarity_tier_label(best_name.to_lower()) + " ✦", 13, best_glow))

	var grid := screen._results_layer.get_node("Center/Panel/Content/ResultsScroll/ResultGrid") as GridContainer
	var column_limit := 5
	if panel_width < 520.0:
		column_limit = 2
	elif panel_width < 760.0:
		column_limit = 3
	elif panel_width < 960.0:
		column_limit = 4
	grid.columns = mini(column_limit, maxi(1, results.size()))
	grid.add_theme_constant_override("h_separation", 12)
	grid.add_theme_constant_override("v_separation", 12)
	var scroll := grid.get_parent() as ScrollContainer
	var viewport_height := screen.get_viewport_rect().size.y
	scroll.custom_minimum_size.y = maxf(100.0,minf(viewport_height - (330.0 if narrow else 210.0), 590.0 if results.size() > grid.columns else 310.0))
	var card_width := clampf((panel_width - 40.0 - float(grid.columns - 1) * 12.0) / float(grid.columns), 118.0, 200.0)
	# Sort the presentation from highest rarity to lowest. The roll results and
	# ownership are untouched; this only makes the reveal easier to scan.
	var ordered_results: Array = results.duplicate()
	ordered_results.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		if bool(a.get("paid_guaranteed", false)) != bool(b.get("paid_guaranteed", false)):
			return bool(a.get("paid_guaranteed", false))
		var rank_a := int(GachaService.RARITY_RANK.get(str(a.get("rarity", "common")).to_lower(), 0))
		var rank_b := int(GachaService.RARITY_RANK.get(str(b.get("rarity", "common")).to_lower(), 0))
		if rank_a != rank_b:
			return rank_a > rank_b
		if bool(a.get("featured", false)) != bool(b.get("featured", false)):
			return bool(a.get("featured", false))
		if bool(a.get("is_new", false)) != bool(b.get("is_new", false)):
			return bool(a.get("is_new", false))
		return str(a.get("character_id", "")) < str(b.get("character_id", ""))
	)
	for index in ordered_results.size():
		var roll: Dictionary = ordered_results[index]
		var card := GachaScreen.SUMMON_RESULT_CARD_SCENE.instantiate() as SummonResultCard
		card.custom_minimum_size = Vector2(card_width, 286.0)
		var portrait := card.get_node("Content/Portrait") as PortraitView
		var portrait_width := minf(132.0, card_width - 16.0)
		portrait.custom_minimum_size = Vector2(portrait_width, portrait_width * 1.5)
		card.setup(roll)
		card.get_node("Content/Status").autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		portrait.show_frame = false
		portrait.show_rarity_effect = false
		grid.add_child(card)
		# These authored portraits have no dynamic frame or aura.
		portrait.set_process(false)
		if GraphicsSettings.quality == 0:
			card.modulate = Color.WHITE
			continue
		card.modulate = Color(1, 1, 1, 0)
		var is_premium := card.premium
		var tween := create_tween()
		if is_premium and GraphicsSettings.quality == 2:
			tween.tween_interval(index * 0.09)
			tween.tween_property(card, "modulate:a", 1.0, 0.16)
			card.pivot_offset = card.custom_minimum_size * 0.5
			card.scale = Vector2(0.9, 0.9)
			tween.tween_property(card, "scale", Vector2.ONE, 0.24).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
			screen._reveal_animations += 1
		else:
			tween.tween_interval(index * 0.055)
			tween.tween_property(card, "modulate:a", 1.0, 0.16)

	var footer := screen._results_layer.get_node("Center/Panel/Content/Footer") as BoxContainer
	footer.vertical = narrow
	for child in footer.get_children():
		if child is Button:
			child.custom_minimum_size.y = 48
	if narrow:
		footer.get_node("Message").hide()
	var again := footer.get_node("SummonAgainButton") as Button
	var next_count := 10 if results.size() >= 10 else 1
	var banner: Dictionary = ContentDB.get_banner(banner_id)
	var cost_data: Dictionary = banner.get("cost", {})
	var next_cost := int(cost_data.get("ten" if next_count == 10 else "single", 0))
	var available_currency := screen.summon_currency(currency_id)
	var paid := currency_id == "paid_moonstones"
	again.text = ("Paid x%d Again" if paid else "Summon x%d Again") % next_count
	again.disabled = next_cost <= 0 or not screen.summon_available(next_count, next_cost, currency_id)
	if again.disabled:
		again.tooltip_text = "Reconnect or check your online %s balance." % ("Paid Moon Stones" if paid else "crystals")
	else:
		again.tooltip_text = "Spend %d %s (balance: %d)." % [next_cost, "Paid Moon Stones" if paid else "crystals", available_currency]
	again.pressed.connect(func() -> void:
		if screen._results_layer != null:
			screen._results_layer.queue_free()
			screen._results_layer = null
		screen._select_banner(banner_id)
		screen._pull(next_count, paid)
	)
	var close := footer.get_node("ContinueButton") as Button
	close.pressed.connect(func() -> void:
		if screen._results_layer != null:
			screen._results_layer.queue_free()
			screen._results_layer = null
	)
	var exit_summon := footer.get_node("ExitSummonButton") as Button
	exit_summon.pressed.connect(screen.close_screen)
	resize_results()


## Additive presentation report (Phase 5). ZERO final portraits exist; featured
## and result PortraitViews all render the procedural fallback.

# Online summons use a separate server wallet/roster. Local progress is never imported.
var online_state: Dictionary = {}
var pending_online: Dictionary = {}
var _online_http: HTTPRequest
var _online_identity := ""
var session_generation := 0
var online_loading := false
var online_request_busy := false

func online_bind() -> void:
	_online_http = HTTPRequest.new()
	_online_http.timeout = 15
	add_child(_online_http)
	AuthGateway.authentication_changed.connect(_online_identity_changed)

func _online_identity_changed(_authenticated: bool, _player: Dictionary) -> void:
	var current := str(AuthGateway.current_player().get("id", ""))
	session_generation += 1
	online_state = {}
	pending_online.clear()
	_online_identity = current
	if not current.is_empty(): _load_pending()
	if is_instance_valid(screen):
		screen._online_mode = true
		screen._invalidate_account_view()
		if AuthGateway.is_authenticated():
			screen._load_default_online.call_deferred()

func _journal_path() -> String:
	return "user://online_summon_pending_" + _online_identity + ".cfg"

func _load_pending() -> void:
	pending_online.clear()
	for path in [_journal_path(), _journal_path() + ".previous"]:
		var cfg := ConfigFile.new()
		if cfg.load(path) != OK: continue
		var data: Variant = cfg.get_value("summon", "pending", {})
		if data is Dictionary:
			pending_online = data
			return

func _store_pending() -> bool:
	var cfg := ConfigFile.new()
	cfg.set_value("summon", "pending", pending_online)
	var path := ProjectSettings.globalize_path(_journal_path())
	var temp := path + ".tmp"
	var backup := path + ".previous"
	if cfg.save(temp) != OK: return false
	if FileAccess.file_exists(path):
		if FileAccess.file_exists(backup): DirAccess.remove_absolute(backup)
		if DirAccess.rename_absolute(path, backup) != OK: return false
	if DirAccess.rename_absolute(temp, path) != OK:
		if FileAccess.file_exists(backup): DirAccess.rename_absolute(backup, path)
		return false
	if FileAccess.file_exists(backup): DirAccess.remove_absolute(backup)
	return true

func _uuid() -> String:
	var bytes := Crypto.new().generate_random_bytes(16)
	bytes[6] = (bytes[6] & 15) | 64
	bytes[8] = (bytes[8] & 63) | 128
	var h := bytes.hex_encode()
	return "%s-%s-%s-%s-%s" % [h.substr(0,8),h.substr(8,4),h.substr(12,4),h.substr(16,4),h.substr(20,12)]

func _online_call(path: String, body: Dictionary = {}) -> Dictionary:
	if online_request_busy:
		return {"code": 0, "error": "Connection busy. Try again."}
	if not AuthGateway.access_token_ready_for_connection():
		return {"code": 0, "error": "Sign in or reconnect, then retry."}
	var identity := str(AuthGateway.current_player().get("id", ""))
	var generation := session_generation
	var err := _online_http.request(AuthGateway.api_base_url + "/v1/summon" + path, PackedStringArray(["Authorization: Bearer " + AuthGateway.access_token_for_request(), "Content-Type: application/json"]), HTTPClient.METHOD_GET if body.is_empty() else HTTPClient.METHOD_POST, "" if body.is_empty() else JSON.stringify(body))
	if err != OK: return {"code": 0, "error": "Connection busy. Try again."}
	online_request_busy = true
	var response: Array = await _online_http.request_completed
	online_request_busy = false
	if generation != session_generation or identity != str(AuthGateway.current_player().get("id", "")):
		return {"code": 0, "error": "Account changed."}
	if response[0] != HTTPRequest.RESULT_SUCCESS:
		return {"code": 0, "error": "Connection interrupted. Retry when connected."}
	var decoder := JSON.new()
	if decoder.parse((response[3] as PackedByteArray).get_string_from_utf8()) != OK or not decoder.data is Dictionary:
		return {"code": 0, "error": "Unexpected server response. Retry when connected."}
	var parsed: Dictionary = decoder.data
	parsed["code"] = int(response[1])
	return parsed

func refresh_online_state() -> bool:
	if online_loading or online_request_busy: return false
	online_loading = true
	var generation := session_generation
	var identity := str(AuthGateway.current_player().get("id", ""))
	if identity.is_empty():
		online_loading = false
		return false
	if identity != _online_identity:
		_online_identity = identity
	_load_pending()
	var response := await _online_call("/state")
	online_loading = false
	if generation != session_generation or identity != _online_identity or identity != str(AuthGateway.current_player().get("id", "")): return false
	if int(response.get("code", 0)) != 200 or str(response.get("playerId", "")) != identity:
		online_state = {}
		if is_instance_valid(screen): screen._invalidate_account_view(false)
		return false
	online_state = response
	AuthGateway.refresh_account_roster()
	return true

func pull_online(banner: String, count: int, currency: String = "crystals") -> Dictionary:
	if _online_identity.is_empty() or _online_identity != str(AuthGateway.current_player().get("id", "")):
		return {"ok": false, "error": "Sign in again."}
	if currency == "paid_moonstones" and not screen.paid_guarantee_verified():
		return {"ok": false, "error": "Paid guarantee not verified. Reconnect to an updated server."}
	if pending_online.is_empty():
		pending_online = {"bannerId": banner, "count": count, "requestId": _uuid(), "currency": currency}
		if currency == "paid_moonstones" and online_state.has("paidTotal"):
			pending_online["expectedPaidTotal"] = str(online_state.paidTotal)
		if not _store_pending():
			pending_online.clear()
			return {"ok": false, "error": "Cannot safely save the summon request."}
	elif pending_online.get("bannerId") != banner or int(pending_online.get("count", 0)) != count or str(pending_online.get("currency","crystals")) != currency:
		return {"ok": false, "error": "Retry the pending summon on its original banner."}
	var request_owner := _online_identity
	var generation := session_generation
	var result := await _online_call("/pull", pending_online)
	if generation != session_generation or request_owner != _online_identity or request_owner != str(AuthGateway.current_player().get("id", "")):
		return {"ok": false, "error": "Account changed. Reopen the original account to recover its summon."}
	var code := int(result.get("code", 0))
	if code == 200 and bool(result.get("ok", false)):
		var confirmed: Dictionary = pending_online.duplicate(true)
		pending_online.clear()
		if not _store_pending():
			pending_online = confirmed
		await refresh_online_state()
		AuthGateway.refresh_online_wallet()
		return result
	if code == 409 and result.get("error") == "paid_progress_changed":
		pending_online.clear()
		_store_pending()
		await refresh_online_state()
		return {"ok": false, "error": "Paid progress changed in another session. Review the refreshed counter before summoning."}
	if code == 400 or (code == 409 and result.get("error") == "insufficient_currency"):
		pending_online.clear()
		_store_pending()
	return {"ok": false, "error": str(result.get("error", "Summon interrupted. Retry the same summon.")).replace("_", " ")}
