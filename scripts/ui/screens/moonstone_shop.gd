extends OverlayScreen
## Sandbox PC checkout only. The client never grants purchased currency.
const LAYOUT = preload("res://scenes/ui/components/moonstone_shop_layout.tscn")
var _layout: VBoxContainer
var _http: HTTPRequest
var _busy := false
var _enabled := false
var _manual_verification := false
var _packages: Array = []
var _orders: Array = []
var _ledger_cursor := ""
var _ledger_busy := false
@onready var _ledger: AcceptDialog = $LedgerDialog
var _pending: Dictionary = {}
var _owner := ""
var _unconfirmed: Dictionary = {}
var _receipt_dialog: FileDialog
var _receipt_text := ""
var _confirm_index := -1
var _spending_dialog: ConfirmationDialog
var _purchase_confirm: ConfirmationDialog
# Bounded, account-scoped polling of the authenticated sandbox reconcile endpoint.
const AUTO_INTERVAL_MS := 8000
const AUTO_MIN_INTERVAL_MS := 5000
const AUTO_MAX_ATTEMPTS := 15
var _auto_order_id := ""
var _auto_due_msec := 0
var _auto_last_msec := 0
var _auto_attempts := 0

func _init() -> void:
	screen_title = "Moonstone Shop"
	screen_subtitle = "PC - test purchases only"

func _build_content() -> void:
	_layout = LAYOUT.instantiate()
	content.add_child(_layout)
	_http = HTTPRequest.new()
	_http.timeout = 20.0
	add_child(_http)
	_owner = str(AuthGateway.current_player().get("id", ""))
	AuthGateway.authentication_changed.connect(_identity_changed)
	AuthGateway.online_wallet_changed.connect(_refresh)
	for i in range(3):
		_layout.get_node("Packages").get_child(i).pressed.connect(_choose.bind(i))
	_layout.get_node("Actions/Refresh").pressed.connect(_load.bind(true))
	_layout.get_node("Actions/Resume").pressed.connect(_resume)
	_layout.get_node("Actions/Cancel").pressed.connect(_cancel_pending)
	_layout.get_node("WalletActions/LedgerButton").pressed.connect(_open_ledger)
	_layout.get_node("WalletActions/Spending").pressed.connect(_open_spending)
	_spending_dialog = _layout.get_node("SpendingDialog")
	_spending_dialog.confirmed.connect(_save_spending)
	_purchase_confirm = _layout.get_node("PurchaseConfirm")
	_purchase_confirm.confirmed.connect(_confirm_checkout)
	_purchase_confirm.canceled.connect(func(): _confirm_index = -1)
	$LedgerDialog/Body/More.pressed.connect(_load_ledger.bind(false))
	$LedgerDialog/Body/Refresh.pressed.connect(_load_ledger.bind(true))
	_layout.get_node("ReceiptActions/Save").pressed.connect(_download_receipt)
	_receipt_dialog = FileDialog.new()
	_receipt_dialog.title = "Save sandbox purchase record"
	_receipt_dialog.access = FileDialog.ACCESS_FILESYSTEM
	_receipt_dialog.file_mode = FileDialog.FILE_MODE_SAVE_FILE
	_receipt_dialog.filters = PackedStringArray(["*.txt ; Text receipt"])
	_receipt_dialog.file_selected.connect(_save_receipt)
	_receipt_dialog.canceled.connect(func(): _receipt_text = "")
	add_child(_receipt_dialog)
	_load.call_deferred(false)

func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_IN and is_node_ready() and _enabled and not _pending.is_empty():
		# Browser return is only a hint to query Stripe, never proof of payment.
		_arm_auto_verification(true, true)

func _arm_auto_verification(reset_budget: bool = false, prompt: bool = false) -> void:
	if not _enabled or _pending.is_empty():
		_auto_due_msec = 0
		_auto_order_id = ""
		return
	var id := str(_pending.get("id", ""))
	if id.is_empty(): return
	if _auto_order_id != id:
		_auto_order_id = id
		_auto_attempts = 0
		_auto_last_msec = 0
	if reset_budget: _auto_attempts = 0
	if _auto_attempts >= AUTO_MAX_ATTEMPTS:
		_auto_due_msec = 0
		return
	var now := Time.get_ticks_msec()
	_auto_due_msec = maxi(now + (1 if prompt else AUTO_INTERVAL_MS), _auto_last_msec + AUTO_MIN_INTERVAL_MS if _auto_last_msec > 0 else 0)

func _process(_delta: float) -> void:
	if _auto_due_msec == 0 or Time.get_ticks_msec() < _auto_due_msec: return
	if _busy or _ledger_busy or not is_node_ready() or is_queued_for_deletion(): return
	if not _enabled or _pending.is_empty() or not AuthGateway.is_authenticated() or _owner != str(AuthGateway.current_player().get("id", "")):
		_auto_due_msec = 0
		return
	_verify_pending_automatically()

func _remember_order(order: Dictionary) -> void:
	for i in range(_orders.size()):
		if str(_orders[i].get("id", "")) == str(order.get("id", "")):
			_orders[i] = order
			return
	_orders.push_front(order)
	if _orders.size() > 30: _orders.resize(30)

func _refund_details(order: Dictionary) -> String:
	var parts := PackedStringArray()
	var amount := int(order.get("refundedCents", 0))
	if amount > 0: parts.append("Stripe refund: EUR %.2f (test)" % (float(amount) / 100.0))
	match str(order.get("reviewReason", "")):
		"spent_or_unattributed_stones": parts.append("Review required: stones spent or not safely attributable. No automatic deduction from later purchases.")
		"partial_refund": parts.append("Partial refund: manual review required.")
		"payment_dispute": parts.append("Payment dispute: manual review required.")
		"wallet_review": parts.append("Wallet review required.")
	return " | ".join(parts)

func _status_for_order(order: Dictionary) -> String:
	match str(order.get("status", "")):
		"credited": return "Test payment verified! %s Moonstones delivered to your online wallet." % UIFactory.number(int(order.get("stones",0)))
		"pending": return "Awaiting test payment. Return after checkout; Reverie checks automatically."
		"expired": return "Checkout closed or expired. No new payment was taken. You can select a new test package."
		"refunded": return "Test payment refunded. Wallet updated by the server."
		"refund_review": return "Refund or dispute requires review. " + _refund_details(order)
		_: return "Payment status: " + str(order.get("status", "unknown"))

func _verify_pending_automatically() -> void:
	if _busy or _pending.is_empty(): return
	_auto_due_msec = 0
	_auto_attempts += 1
	_auto_last_msec = Time.get_ticks_msec()
	var order_id := str(_pending.id)
	_busy = true
	_refresh()
	var result := await _call("/reconcile", {"orderId": order_id})
	if not is_inside_tree() or is_queued_for_deletion(): return
	_busy = false
	if result.get("code",0) == 200 and result.get("order") is Dictionary and str(result.order.get("id", "")) == order_id:
		_remember_order(result.order)
		_pending = result.order if result.order.status == "pending" else {}
		_set_status(_status_for_order(result.order))
		if _pending.is_empty(): AuthGateway.refresh_online_wallet()
	else:
		_set_status("Verification temporarily unavailable. You can retry with Refresh payment status.")
	_arm_auto_verification()
	if not _pending.is_empty() and _auto_due_msec == 0:
		_set_status("Automatic check paused. Return to the game or press Refresh payment status to retry.")
	_refresh()

func _identity_changed(_authenticated: bool, _player: Dictionary) -> void:
	if str(AuthGateway.current_player().get("id", "")) != _owner:
		close_screen()

func _refresh() -> void:
	if _layout == null: return
	_layout.get_node("Balance").text = "Online Moonstone balance: " + UIFactory.number(int(AuthGateway.online_currencies.get("paid_moonstones",0)))
	for i in range(3):
		var button := _layout.get_node("Packages").get_child(i) as Button
		if i < _packages.size():
			var pack: Dictionary = _packages[i]
			button.text = "%s Moonstones\nBUY - EUR %.2f (TEST)" % [UIFactory.number(int(pack.stones)),float(pack.amountCents)/100.0]
		button.disabled = _busy or not _enabled or not _pending.is_empty() or not _unconfirmed.is_empty() or i>=_packages.size()
	_layout.get_node("Actions/Refresh").disabled = _busy or _owner.is_empty()
	_layout.get_node("WalletActions/LedgerButton").disabled = _busy or _ledger_busy or _owner.is_empty()
	_layout.get_node("WalletActions/Spending").disabled = _busy or _owner.is_empty()
	_layout.get_node("Actions/Resume").disabled = _busy or not _enabled or (_pending.is_empty() and _unconfirmed.is_empty())
	_layout.get_node("Actions/Cancel").disabled = _busy or not _enabled or _pending.is_empty()
	var selector := _layout.get_node("ReceiptActions/Order") as OptionButton
	var selected_id := str(selector.get_item_metadata(selector.selected)) if selector.selected >= 0 else ""
	selector.clear()
	var selected_index := 0
	for order in _orders:
		if order.get("creditedAt") == null or str(order.get("status", "")) not in ["credited", "refund_review", "refunded"]: continue
		selector.add_item("%s | %s stones | %s" % [str(order.createdAt).left(10), UIFactory.number(int(order.stones)), str(order.status).replace("_", " ")])
		var index := selector.item_count - 1
		selector.set_item_metadata(index, str(order.id))
		if str(order.id) == selected_id: selected_index = index
	if selector.item_count == 0:
		selector.add_item("No verified receipts yet")
		selector.set_item_metadata(0, "")
	selector.select(selected_index)
	selector.disabled = _busy or str(selector.get_item_metadata(selected_index)).is_empty()
	_layout.get_node("ReceiptActions/Save").disabled = selector.disabled or _owner.is_empty()
	var lines := PackedStringArray()
	for row in _orders:
		lines.append("%s  |  %d Moonstones  |  EUR %.2f  |  %s" % [str(row.createdAt).left(10),int(row.stones),float(row.amountCents)/100.0,str(row.status).replace("_"," ").capitalize()] + "\nOrder ID: " + str(row.id))
		var refund_detail := _refund_details(row)
		if not refund_detail.is_empty(): lines.append(refund_detail)
	_layout.get_node("HistoryScroll/History").text = "\n".join(lines) if not lines.is_empty() else "No test purchases yet."

func _set_status(value: String) -> void:
	if is_instance_valid(_layout): _layout.get_node("Status").text = value

func _call(path: String, payload: Dictionary = {}) -> Dictionary:
	if _owner.is_empty() or not AuthGateway.access_token_ready_for_connection() or _owner != str(AuthGateway.current_player().get("id","")):
		return {"code":0,"error":"Sign in to access the online shop."}
	var headers := PackedStringArray(["Authorization: Bearer "+AuthGateway.access_token_for_request(),"Content-Type: application/json"])
	var err := _http.request(AuthGateway.api_base_url+"/v1/shop"+path,headers,HTTPClient.METHOD_GET if payload.is_empty() else HTTPClient.METHOD_POST,"" if payload.is_empty() else JSON.stringify(payload))
	if err != OK: return {"code":0,"error":"Connection busy."}
	var response: Array = await _http.request_completed
	if _owner != str(AuthGateway.current_player().get("id","")): return {"code":0,"error":"Account changed."}
	var data: Variant = JSON.parse_string((response[3] as PackedByteArray).get_string_from_utf8())
	if response[0]!=HTTPRequest.RESULT_SUCCESS or not data is Dictionary: return {"code":0,"error":"Connection interrupted."}
	data["code"] = int(response[1])
	if data.code==200 and str(data.get("playerId",""))!=_owner: return {"code":0,"error":"Account mismatch."}
	return data

func _load(reconcile: bool = false) -> void:
	if _busy: return
	if OS.get_name() in ["Android","iOS","Web"]:
		_set_status("PC sandbox only. Mobile stores are not connected.")
		return
	_busy = true
	_refresh()
	var catalogue := await _call("/catalog")
	if catalogue.get("code",0)!=200:
		_enabled=false
		_busy=false
		_set_status("Shop unavailable. Sign in and run the updated API.")
		_refresh()
		return
	_enabled = bool(catalogue.get("enabled",false)) and bool(catalogue.get("testMode",false))
	_manual_verification = catalogue.get("verificationMode", "disabled") == "manual"
	_packages = catalogue.get("packages",[])
	_layout.get_node("Description").text = "Local sandbox: return here after checkout for automatic verification, or press Refresh payment status. No webhook listener is connected. No real money or live entitlement." if _manual_verification else "Test Moonstones are credited to the signed-in online wallet only after server verification. Prices are provisional. No card details are collected by Reverie."
	var history := await _call("/orders")
	if history.get("code",0)==200:
		_orders = history.get("orders",[])
		# A lost checkout response may have created a server order already.
		if not _unconfirmed.is_empty():
			for row in _orders:
				if str(row.get("requestId", "")) == str(_unconfirmed.get("requestId", "")):
					_unconfirmed = {}
					break
		_pending = {}
		for row in _orders:
			if row.status=="pending":
				_pending = row
				break
		var verify_order: Dictionary = _pending
		if _manual_verification and verify_order.is_empty():
			for row in _orders:
				if row.status in ["credited", "refund_review"]:
					verify_order = row
					break
		if reconcile and _enabled and not verify_order.is_empty():
			var check := await _call("/reconcile",{"orderId":verify_order.id})
			if check.get("code",0)==200:
				_remember_order(check.order)
				_pending = check.order if check.order.status=="pending" else {}
				_set_status(_status_for_order(check.order))
			else: _set_status("Verification unavailable. Try refreshing again.")
		elif not _enabled: _set_status("Stripe sandbox is not connected. No checkout is enabled.")
		else: _set_status("Select a test package." if _pending.is_empty() else _status_for_order(_pending))
	else:
		_enabled = false
		_set_status("Purchase history unavailable; checkout disabled until refreshed.")
	AuthGateway.refresh_online_wallet()
	_busy=false
	_arm_auto_verification(reconcile, not reconcile)
	_refresh()

func _uuid() -> String:
	var bytes := Crypto.new().generate_random_bytes(16)
	bytes[6] = (bytes[6] & 15) | 64
	bytes[8] = (bytes[8] & 63) | 128
	var h := bytes.hex_encode()
	return "%s-%s-%s-%s-%s" % [h.substr(0,8),h.substr(8,4),h.substr(12,4),h.substr(16,4),h.substr(20,12)]

func _choose(index: int) -> void:
	if _busy or not _enabled or index>=_packages.size() or not _pending.is_empty() or not _unconfirmed.is_empty(): return
	if _purchase_confirm.visible: return
	_confirm_index = index
	var pack: Dictionary = _packages[index]
	_purchase_confirm.dialog_text = "%s Paid Moonstones for EUR %.2f (TEST).\n\nContinue to Stripe sandbox? No real money will be charged." % [UIFactory.number(int(pack.stones)),float(pack.amountCents)/100.0]
	_purchase_confirm.popup_centered(Vector2i(480,230))

func _confirm_checkout() -> void:
	var index := _confirm_index
	_confirm_index = -1
	if _busy or not _enabled or index < 0 or index >= _packages.size() or not _pending.is_empty() or not _unconfirmed.is_empty(): return
	_unconfirmed = {"packageId":_packages[index].id,"requestId":_uuid()}
	await _checkout(_unconfirmed)

func _resume() -> void:
	if _busy or not _enabled: return
	if not _unconfirmed.is_empty(): await _checkout(_unconfirmed)
	elif not _pending.is_empty(): await _checkout({"packageId":_pending.packageId,"requestId":_pending.requestId})

func _checkout(payload: Dictionary) -> void:
	_busy = true
	_refresh()
	var result := await _call("/checkout",payload)
	_busy = false
	if result.get("code",0)!=200:
		if result.get("error", "") == "pending_checkout_exists" and str(result.get("playerId", "")) == _owner and result.get("order") is Dictionary:
			_unconfirmed = {}
			_pending = result.order
			_remember_order(_pending)
			_arm_auto_verification(true)
			_set_status("An earlier checkout is still pending. Resume or cancel it first.")
		elif result.get("error", "") == "spending_limit_reached" and str(result.get("playerId", "")) == _owner:
			_unconfirmed = {}
			_set_status("Your %s spending limit prevents this purchase. Review Spending limits & summary." % str(result.get("period", "configured")))
		else: _set_status("Checkout unavailable. Resume the same request instead of creating another purchase.")
		_refresh()
		return
	_unconfirmed = {}
	_pending = result.order if result.order.status=="pending" else {}
	_remember_order(result.order)
	var url := str(result.get("checkoutUrl",""))
	if url.begins_with("https://checkout.stripe.com/"):
		var opened := OS.shell_open(url)
		_set_status("Complete the TEST checkout in your browser. Return here for automatic verification." if opened==OK else "Browser could not open. Resume checkout to try again.")
	else: _set_status(_status_for_order(result.order))
	AuthGateway.refresh_online_wallet()
	_arm_auto_verification(true)
	_refresh()

func _cancel_pending() -> void:
	if _busy or not _enabled or _pending.is_empty(): return
	var order_id := str(_pending.id)
	_auto_due_msec = 0
	_busy = true
	_set_status("Checking Stripe before closing this unpaid checkout...")
	_refresh()
	var result := await _call("/cancel", {"orderId":order_id})
	if not is_inside_tree() or is_queued_for_deletion(): return
	_busy = false
	if result.get("code",0) == 200 and result.get("order") is Dictionary and str(result.order.get("id", "")) == order_id:
		_remember_order(result.order)
		_pending = result.order if result.order.status == "pending" else {}
		_unconfirmed = {}
		_set_status(_status_for_order(result.order))
		AuthGateway.refresh_online_wallet()
	else:
		_set_status("Cancellation not confirmed. Resume or refresh the existing checkout; no new purchase was created.")
	_arm_auto_verification(true)
	_refresh()

func _money(cents: int) -> String:
	return "EUR %.2f" % (float(cents) / 100.0)

func _limit_text(value: Variant) -> String:
	return "" if value == null else "%.2f" % (float(value) / 100.0)

func _parse_limit(value: String) -> Variant:
	var cleaned := value.strip_edges()
	if cleaned.is_empty(): return null
	var pattern := RegEx.new()
	pattern.compile("^[0-9]{1,7}([.,][0-9]{1,2})?$")
	if pattern.search(cleaned) == null: return -1
	var cents := roundi(cleaned.replace(",", ".").to_float() * 100.0)
	return cents if cents <= 100000000 else -1

func _show_spending(data: Dictionary) -> void:
	_spending_dialog.get_node("Body/Summary").text = "Today committed: %s\nThis month committed: %s\nPending checkout: %s (included above)" % [_money(int(data.get("dailyCommittedCents",0))),_money(int(data.get("monthlyCommittedCents",0))),_money(int(data.get("pendingCents",0)))]
	_spending_dialog.get_node("Body/Daily").text = _limit_text(data.get("dailyCents"))
	_spending_dialog.get_node("Body/Monthly").text = _limit_text(data.get("monthlyCents"))

func _open_spending() -> void:
	if _busy or _spending_dialog.visible: return
	_busy = true
	_refresh()
	var result := await _call("/spending")
	if not is_inside_tree() or is_queued_for_deletion(): return
	_busy = false
	_refresh()
	if result.get("code",0) != 200 or not result.get("testMode",false) or not result.get("spending") is Dictionary:
		_set_status("Spending summary unavailable. Refresh and try again.")
		return
	_show_spending(result.spending)
	_spending_dialog.get_node("Body/Message").text = ""
	_spending_dialog.popup_centered(Vector2i(560,360))

func _save_spending() -> void:
	if _busy: return
	var daily: Variant = _parse_limit(_spending_dialog.get_node("Body/Daily").text)
	var monthly: Variant = _parse_limit(_spending_dialog.get_node("Body/Monthly").text)
	var msg: Label = _spending_dialog.get_node("Body/Message")
	if daily == -1 or monthly == -1:
		msg.text = "Enter a nonnegative EUR amount with up to two decimals, or leave blank."
		return
	_busy = true
	_spending_dialog.get_ok_button().disabled = true
	var result := await _call("/spending", {"dailyCents":daily,"monthlyCents":monthly})
	if not is_inside_tree() or is_queued_for_deletion(): return
	_busy = false
	_spending_dialog.get_ok_button().disabled = false
	_refresh()
	if result.get("code",0) != 200 or not result.get("testMode",false):
		msg.text = "Could not save limits. Try again."
		return
	_spending_dialog.hide()
	_set_status("Your sandbox spending limits were saved.")

func _download_receipt() -> void:
	if _busy or _receipt_dialog.visible: return
	var selector := _layout.get_node("ReceiptActions/Order") as OptionButton
	if selector.selected < 0: return
	var order_id := str(selector.get_item_metadata(selector.selected))
	if order_id.is_empty(): return
	_busy = true
	_refresh()
	var result := await _call("/receipt/" + order_id.uri_encode())
	if not is_inside_tree() or is_queued_for_deletion(): return
	_busy = false
	_refresh()
	if result.get("code",0) != 200 or not result.get("testMode",false) or str(result.get("orderId","")) != order_id:
		_set_status("Receipt unavailable. Refresh purchase history and try again.")
		return
	_receipt_text = str(result.get("receipt", ""))
	if _receipt_text.is_empty(): return
	_receipt_dialog.current_file = "reverie-test-receipt-" + order_id + ".txt"
	_receipt_dialog.popup_centered_ratio(0.75)

func _save_receipt(path: String) -> void:
	if _receipt_text.is_empty() or _owner != str(AuthGateway.current_player().get("id", "")):
		_receipt_text = ""
		return
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		_set_status("Could not save receipt. Choose a writable location.")
	else:
		file.store_string(_receipt_text)
		file.close()
		_set_status("Sandbox purchase record saved.")
	_receipt_text = ""

func _open_ledger() -> void:
	if _busy or _ledger_busy or _owner.is_empty(): return
	var viewport := get_tree().root.get_visible_rect().size
	_ledger.popup_centered(Vector2i(int(minf(650.0,viewport.x-36.0)),int(minf(510.0,viewport.y-36.0))))
	await _load_ledger(true)

func _load_ledger(first: bool) -> void:
	if _busy or _ledger_busy or not _ledger.visible or (not first and _ledger_cursor.is_empty()): return
	_ledger_busy = true
	_busy = true
	_refresh()
	var entries: VBoxContainer = $LedgerDialog/Body/Scroll/Entries
	var summary: Label = $LedgerDialog/Body/Summary
	var more: Button = $LedgerDialog/Body/More
	if first:
		_ledger_cursor = ""
		for child in entries.get_children():
			entries.remove_child(child)
			child.queue_free()
	more.disabled = true
	summary.text = "Loading verified server transactions..."
	var path := "/ledger?limit=20"
	if not first: path += "&before=" + _ledger_cursor.uri_encode()
	var result := await _call(path)
	_ledger_busy = false
	_busy = false
	if not is_inside_tree() or _owner != str(AuthGateway.current_player().get("id","")): return
	_refresh()
	if result.get("code",0) != 200:
		summary.text = "Transaction history unavailable. Refresh to retry."
		more.disabled = _ledger_cursor.is_empty()
		return
	summary.text = "Server balance: %s Paid Moon Stones. Sandbox purchases only." % str(result.get("balance","0"))
	for row in result.get("entries",[]):
		var panel := UIFactory.panel(Color("#11172a"), UITheme.BORDER_SOFT, 8, 1, 10)
		var details := UIFactory.vbox(5)
		panel.add_child(details)
		entries.add_child(panel)
		var delta := str(row.get("delta","0"))
		var label := str(row.get("reason","transaction")).replace("_"," ").capitalize()
		match row.get("reason"):
			"stripe_sandbox_purchase": label = "Verified test purchase"
			"stripe_sandbox_refund": label = "Test purchase refund"
			"gacha_pull": label = "Paid summon"
		var change := ("+" + delta) if not delta.begins_with("-") else delta
		details.add_child(UIFactory.wrapped("%s | %s Moon Stones | Balance: %s" % [label,change,str(row.get("balanceAfter","0"))],14,UITheme.GREEN if not delta.begins_with("-") else UITheme.GOLD))
		var order: Variant = row.get("order")
		var summon: Variant = row.get("summon")
		if order is Dictionary:
			details.add_child(UIFactory.wrapped("Order: %s | EUR %.2f | %s" % [str(order.id),float(order.amountCents)/100.0,str(order.status).replace("_"," ").capitalize()],12,UITheme.TEXT_DIM))
		elif summon is Dictionary:
			var banner := ContentDB.get_banner(str(summon.bannerId))
			details.add_child(UIFactory.wrapped("%s x%d | Summon: %s" % [str(banner.get("name",summon.bannerId)),int(summon.count),str(summon.id)],12,UITheme.TEXT_DIM))
		else:
			details.add_child(UIFactory.wrapped("Reference: " + str(row.get("referenceId","")),12,UITheme.TEXT_DIM))
		details.add_child(UIFactory.wrapped(str(row.get("createdAt","")).replace("T"," ").substr(0,19)+" UTC | Ledger ID: "+str(row.get("id","")),11,UITheme.TEXT_DIM))
	if entries.get_child_count() == 0:
		entries.add_child(UIFactory.wrapped("No recorded Paid Moon Stone transactions.",14,UITheme.TEXT_DIM))
	_ledger_cursor = "" if result.get("nextCursor") == null else str(result.nextCursor)
	more.disabled = _ledger_cursor.is_empty()
	more.text = "No older transactions" if more.disabled else "Load older transactions"
