extends AcceptDialog
## Server-only summon records. Never reads or modifies the local wallet.
const MOB := preload("res://scripts/gacha/mob_summon_reward.gd")
const UPGRADE := preload("res://scripts/gacha/character_upgrade_card.gd")
@onready var _request: HTTPRequest = $HistoryRequest
@onready var _summary: Label = $Body/Summary
@onready var _filter: OptionButton = $Body/Filters/Currency
@onready var _entries: VBoxContainer = $Body/Scroll/Entries
@onready var _more: Button = $Body/More
var _cursor := ""
var _identity := ""
var _generation := 0
var _busy := false

func _ready() -> void:
	_filter.add_item("All summons")
	_filter.add_item("Paid Moon Stones")
	_filter.add_item("Ordinary crystals")
	_filter.add_item("Paid guarantee audit")
	_filter.item_selected.connect(func(_index: int): _reload())
	$Body/Filters/Refresh.pressed.connect(_reload)
	_more.pressed.connect(func(): _fetch(false))
	AuthGateway.authentication_changed.connect(_account_changed)
	close_requested.connect(_invalidate)
	confirmed.connect(_invalidate)

func open_history() -> void:
	var viewport := get_tree().root.get_visible_rect().size
	popup_centered(Vector2i(int(minf(660.0, viewport.x - 36.0)), int(minf(560.0, viewport.y - 36.0))))
	_reload()

func _invalidate() -> void:
	_generation += 1
	_request.cancel_request()
	_busy = false
	_identity = ""
	_cursor = ""
	_clear_entries()

func _account_changed(_authenticated: bool, _player: Dictionary) -> void:
	if _identity != str(AuthGateway.current_player().get("id", "")):
		_invalidate()
		hide()

func _clear_entries() -> void:
	for child in _entries.get_children():
		_entries.remove_child(child)
		child.queue_free()

func _reload() -> void:
	_generation += 1
	_request.cancel_request()
	_busy = false
	_cursor = ""
	_clear_entries()
	_fetch(true)

func _fetch(first: bool) -> void:
	if _busy or not visible or (not first and _cursor.is_empty()):
		return
	_identity = str(AuthGateway.current_player().get("id", ""))
	if _identity.is_empty() or not AuthGateway.access_token_ready_for_connection():
		_summary.text = "Sign in or reconnect to view your summon history."
		_more.disabled = true
		return
	var generation := _generation
	var owner := _identity
	var path := "/v1/summon/history?limit=10"
	if _filter.selected == 3:
		path = "/v1/summon/guarantee-audit"
	elif _filter.selected == 1:
		path += "&currency=paid_moonstones"
	elif _filter.selected == 2:
		path += "&currency=crystals"
	if not first:
		path += "&before=" + _cursor.uri_encode()
	_busy = true
	_more.disabled = true
	_summary.text = "Loading server history..."
	var err := _request.request(AuthGateway.api_base_url + path, PackedStringArray(["Authorization: Bearer " + AuthGateway.access_token_for_request()]))
	if err != OK:
		_busy = false
		_summary.text = "Connection unavailable. Refresh to retry."
		return
	var response: Array = await _request.request_completed
	if generation != _generation or owner != str(AuthGateway.current_player().get("id", "")) or not visible:
		return
	_busy = false
	var parsed: Variant = JSON.parse_string((response[3] as PackedByteArray).get_string_from_utf8())
	if response[0] != HTTPRequest.RESULT_SUCCESS or int(response[1]) != 200 or not parsed is Dictionary or str(parsed.get("playerId", "")) != owner:
		_summary.text = "Could not load history. Refresh to retry."
		_more.disabled = _cursor.is_empty()
		return
	if _filter.selected == 3:
		_show_audit(parsed)
		return
	var progress := int(parsed.get("paidProgress", 0))
	var milestone := int(parsed.get("paidMilestone", 100))
	_summary.text = "Paid featured guarantee: %d / %d  |  %d remaining" % [progress, milestone, milestone - progress]
	for entry in parsed.get("entries", []):
		_add_entry(entry)
	if _entries.get_child_count() == 0:
		_entries.add_child(UIFactory.wrapped("No recorded summons for this filter.", 14, UITheme.TEXT_DIM))
	_cursor = "" if parsed.get("nextCursor") == null else str(parsed.nextCursor)
	_more.disabled = _cursor.is_empty()
	_more.text = "No older summons" if _cursor.is_empty() else "Load older summons"

func _add_entry(entry: Dictionary) -> void:
	var panel := UIFactory.panel(Color("#11172a"), UITheme.BORDER_SOFT, 8, 1, 10)
	var box := UIFactory.vbox(6)
	panel.add_child(box)
	_entries.add_child(panel)
	var date := str(entry.get("createdAt", "")).replace("T", " ").substr(0, 19) + " UTC"
	var currency := "Paid Moon Stones" if entry.get("currency") == "paid_moonstones" else "Crystals"
	box.add_child(UIFactory.wrapped("%s  |  x%d  |  %s %s" % [str(entry.get("bannerName", "")), int(entry.get("count", 0)), str(entry.get("spent", "0")), currency], 14, UITheme.GOLD))
	box.add_child(UIFactory.wrapped(date + "  |  ID: " + str(entry.get("id", "")), 11, UITheme.TEXT_DIM))
	for roll in entry.get("results", []):
		var id := str(roll.get("character_id", ""))
		var rarity := str(roll.get("rarity", "common"))
		var definition: CharacterDef = ContentDB.get_character(id)
		var mob := MOB.definition(id)
		var card := UPGRADE.definition(id)
		var display_name := definition.display_name if definition != null else id
		if not mob.is_empty():
			display_name = str(mob.get("name", id)) + " - " + MOB.description(roll.get("reward_items", {}))
		elif not card.is_empty():
			display_name = str(card.get("name", id)) + " upgrade card"
		var tags := ""
		if bool(roll.get("paid_guaranteed", false)):
			tags = " | PAID MILESTONE"
			if bool(roll.get("featured", false)):
				tags += " - FEATURED"
		elif bool(roll.get("featured", false)):
			tags = " | FEATURED"
		box.add_child(UIFactory.wrapped("%s - %s%s" % [rarity.capitalize(), display_name, tags], 13, UITheme.rarity_color(rarity)))

func _show_audit(report: Dictionary) -> void:
	_more.disabled = true
	_more.text = "End of guarantee audit"
	_cursor = ""
	var total := int(report.get("totalPaidPulls", 0))
	_summary.text = "%d recorded paid summons | %d expected milestones" % [total,int(report.get("expectedMilestones",0))]
	if not bool(report.get("historyComplete",false)):
		_summary.text += "\nSome historical records cannot be verified. Contact support for missing transactions."
	_entries.add_child(UIFactory.wrapped("Review requests are checked against server records. No reward or refund is granted automatically.",13,UITheme.TEXT_DIM))
	var cases: Array = report.get("cases",[])
	if cases.is_empty():
		_entries.add_child(UIFactory.wrapped("No recorded guarantee milestones to review.",14,UITheme.TEXT_DIM))
	for entry in cases:
		var panel := UIFactory.panel(Color("#11172a"),UITheme.BORDER_SOFT,8,1,10)
		var box := UIFactory.vbox(6)
		panel.add_child(box)
		_entries.add_child(panel)
		var banner := ContentDB.get_banner(str(entry.bannerId))
		var status := str(entry.status)
		var title_text := "Featured reward recorded" if status == "fulfilled" else ("Missed featured guarantee" if status == "missed_featured" else "Needs manual review")
		box.add_child(UIFactory.wrapped(title_text + " | " + str(banner.get("name",entry.bannerId)),14,UITheme.GREEN if status == "fulfilled" else UITheme.GOLD))
		var definition: CharacterDef = ContentDB.get_character(str(entry.characterId))
		var character_name := definition.display_name if definition != null else str(entry.characterId)
		box.add_child(UIFactory.wrapped("Recorded reward: " + character_name + " | Roll " + str(int(entry.rollIndex)+1) + "\nSummon ID: " + str(entry.pullId),12,UITheme.TEXT_DIM))
		if status != "fulfilled":
			var review: Variant = entry.get("reviewStatus")
			if review != null:
				box.add_child(UIFactory.wrapped("Review: " + str(review).replace("_"," ").capitalize(),13,UITheme.VIOLET))
				if review == "resolved" and entry.get("grantedCharacter") != null:
					var granted: CharacterDef = ContentDB.get_character(str(entry.grantedCharacter))
					var granted_name := granted.display_name if granted != null else str(entry.grantedCharacter)
					box.add_child(UIFactory.wrapped("Compensation delivered: " + granted_name,14,UITheme.GREEN))
			else:
				var button := UIFactory.button("Request support review")
				button.pressed.connect(_request_review.bind(str(entry.pullId),int(entry.rollIndex),button))
				box.add_child(button)

func _request_review(pull_id: String, index: int, button: Button) -> void:
	if _busy or not visible or not AuthGateway.access_token_ready_for_connection():
		return
	var generation := _generation
	var owner := _identity
	_busy = true
	button.disabled = true
	var payload := JSON.stringify({"pullId":pull_id,"rollIndex":index})
	var err := _request.request(AuthGateway.api_base_url+"/v1/summon/guarantee-review",PackedStringArray(["Authorization: Bearer "+AuthGateway.access_token_for_request(),"Content-Type: application/json"]),HTTPClient.METHOD_POST,payload)
	if err != OK:
		_busy = false
		button.disabled = false
		_summary.text = "Review request could not connect. Retry."
		return
	var response: Array = await _request.request_completed
	if generation != _generation or owner != str(AuthGateway.current_player().get("id","")) or not visible:
		return
	_busy = false
	var parsed: Variant = JSON.parse_string((response[3] as PackedByteArray).get_string_from_utf8())
	if response[0] != HTTPRequest.RESULT_SUCCESS or int(response[1]) != 200 or not parsed is Dictionary or str(parsed.get("playerId","")) != owner:
		if is_instance_valid(button): button.disabled = false
		_summary.text = "Review request unavailable. Retry or refresh."
		return
	_reload()
