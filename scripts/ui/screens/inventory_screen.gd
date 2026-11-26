class_name InventoryScreen
extends OverlayScreen
## Inventory and equipment management refactored into reusable item/inventory/equipment modules.
## GameState remains the authoritative source for inventory, equipment, upgrades, and saves.

const INVENTORY_LAYOUT_SCENE: PackedScene = preload("res://scenes/ui/components/inventory_screen_layout.tscn")
const ITEM_ACQUISITION_NOTIFICATION_SCENE: PackedScene = preload("res://scenes/items/ui/item_acquisition_notification.tscn")
const _InventoryControllerScript = preload("res://scripts/items/inventory/inventory_controller.gd")
const _ItemInteractionScript = preload("res://scripts/items/item_interaction.gd")

var _controller = null
var _notification = null
var grid_component: InventoryGridComponent
var crafting_component: InventoryCraftingComponent
var _crafting_window: PanelContainer:
	get:
		return crafting_component._window if crafting_component != null else null
var _crafting_list: VBoxContainer:
	get:
		return crafting_component._list if crafting_component != null else null


func _init() -> void:
	screen_title = "Inventory"
	screen_subtitle = "Materials, gear and currencies carried by the party"


func _build_content() -> void:
	_inventory_mode = CheckButton.new()
	_inventory_mode.text = "Online inventory"
	header_actions.add_child(_inventory_mode)
	_inventory_mode.hide()
	AuthGateway.online_wallet_changed.connect(_refresh_online_inventory)
	AuthGateway.authentication_changed.connect(_inventory_identity_changed)
	_set_inventory_mode(AuthGateway.is_authenticated())

func _build_local_inventory() -> void:
	_controller = _InventoryControllerScript.new()
	add_child(_controller)
	_controller.inventory_updated.connect(_refresh)

	var layout := INVENTORY_LAYOUT_SCENE.instantiate() as VBoxContainer
	layout.size_flags_vertical = Control.SIZE_EXPAND_FILL
	content.add_child(layout)
	_local_layout = layout

	var wallet := layout.get_node("Wallet") as HBoxContainer
	wallet.add_child(UIFactory.chip("Gold  " + UIFactory.number(GameState.inventory_domain.currency("gold")), UITheme.GOLD))
	wallet.add_child(UIFactory.chip("Crystals  " + UIFactory.number(GameState.inventory_domain.currency("crystals")), UITheme.TEAL))
	wallet.add_child(UIFactory.chip("Gems  " + UIFactory.number(GameState.inventory_domain.currency("gems")), UITheme.VIOLET))

	grid_component = layout.get_node("GridComponent") as InventoryGridComponent
	crafting_component = layout.get_node("CraftingComponent") as InventoryCraftingComponent
	if grid_component != null:
		grid_component.bind(self)
		grid_component.build(layout)
		grid_component.refresh()
	if crafting_component != null:
		crafting_component.bind(self)
		crafting_component.build(layout.get_node("Filters") as HBoxContainer)

	_notification = ITEM_ACQUISITION_NOTIFICATION_SCENE.instantiate() as ItemAcquisitionNotification
	content.add_child(_notification)
	_controller.notification_requested.connect(_notification.show_message)

func _set_filter(value: String) -> void:
	if grid_component != null:
		grid_component.set_filter(value)

func _refresh() -> void:
	if grid_component != null:
		grid_component.refresh()

func _rebuild_grid() -> void:
	if grid_component != null:
		grid_component.rebuild_grid()

func _collect_item_ids() -> Array[String]:
	return grid_component.collect_item_ids() if grid_component != null else []

func _make_card(item_id: String) -> PanelContainer:
	return grid_component.make_card(item_id) if grid_component != null else PanelContainer.new()

func _show_detail(item_id: String) -> void:
	if grid_component != null:
		grid_component.show_detail(item_id)

func _equipped_by(item_id: String) -> Array:
	return grid_component.equipped_by(item_id) if grid_component != null else []

func _on_enhance_requested(uid: String, slot: String) -> void:
	var result: Dictionary = _ItemInteractionScript.upgrade(uid, slot)
	EventBus.toast_requested.emit(str(result.get("reason", "Equipment enhanced! Stats increased by 8%." if result.get("ok", false) else "Could not enhance equipment.")))
	_rebuild_grid()


func _on_unequip_requested(uid: String, slot: String) -> void:
	var result: Dictionary = _ItemInteractionScript.unequip(uid, slot)
	EventBus.toast_requested.emit("Item unequipped." if bool(result.get("ok", false)) else str(result.get("reason", "Could not unequip that item.")))
	_rebuild_grid()


func _on_equip_requested(item_id: String, uid: String) -> void:
	if uid.is_empty():
		EventBus.toast_requested.emit("Choose a character first.")
		return
	var result: Dictionary = _ItemInteractionScript.equip(uid, item_id)
	if bool(result.get("ok", false)):
		AudioDirector.play_inventory_equip()
	EventBus.toast_requested.emit("Equipment updated." if bool(result.get("ok", false)) else str(result.get("reason", "Could not equip that item.")))
	_rebuild_grid()


func _on_use_requested(item_id: String) -> void:
	var result: Dictionary = _ItemInteractionScript.use(item_id)
	EventBus.toast_requested.emit(str(result.get("reason", "Could not use item.")))
	_rebuild_grid()



func _refresh_crafting_window() -> void:
	if crafting_component != null:
		crafting_component.refresh()


var _online_inventory_panel: VBoxContainer
var _online_layout: VBoxContainer
var _local_layout: VBoxContainer
var _inventory_mode: CheckButton
var _online_mode := false
var _online_poll_at := 0

func _set_inventory_mode(_value: bool = true) -> void:
	_online_mode = true
	_inventory_mode.hide()
	if _local_layout != null: _local_layout.hide()
	if is_instance_valid(_notification): _notification.hide()
	if _online_layout == null: _build_online_inventory()
	_online_layout.show()
	_refresh_online_inventory()
	if AuthGateway.is_authenticated(): AuthGateway.refresh_online_wallet()


func _inventory_identity_changed(_authenticated: bool, _player: Dictionary) -> void:
	_set_inventory_mode(AuthGateway.is_authenticated())

func _process(_delta: float) -> void:
	if not _online_mode or not AuthGateway.is_authenticated() or not is_visible_in_tree(): return
	var now := Time.get_ticks_msec()
	if now >= _online_poll_at:
		_online_poll_at = now+5000
		AuthGateway.refresh_online_wallet()

func _build_online_inventory() -> void:
	_online_layout = preload("res://scenes/ui/components/online_inventory_layout.tscn").instantiate() as VBoxContainer
	content.add_child(_online_layout)
	_online_inventory_panel = _online_layout.get_node("Scroll/Materials") as VBoxContainer
	var categories: OptionButton = _online_layout.get_node("Filters/Category")
	for value in ["All","Materials","Equipment","Upgrade cards","Other"]:
		categories.add_item(value)
	categories.item_selected.connect(func(_i): _refresh_online_inventory())
	_online_layout.get_node("Filters/Search").text_changed.connect(func(_q): _refresh_online_inventory())
	_online_layout.get_node("Filters/Refresh").pressed.connect(AuthGateway.refresh_online_wallet)

var _online_inventory_signature: Array = []

func _refresh_online_inventory() -> void:
	if not _online_mode or not is_instance_valid(_online_inventory_panel): return
	var signature: Array = [str(AuthGateway.current_player().get("id","")),AuthGateway.is_authenticated(),AuthGateway.online_wallet.is_empty(),AuthGateway.online_currencies.duplicate(true),AuthGateway.online_inventory.duplicate(true),_online_layout.get_node("Filters/Search").text.strip_edges().to_lower(),_online_layout.get_node("Filters/Category").selected]
	if signature == _online_inventory_signature: return
	_online_inventory_signature = signature
	var wallet := _online_layout.get_node("Wallet")
	UIFactory.clear(wallet)
	UIFactory.clear(_online_inventory_panel)
	var status: Label = _online_layout.get_node("Status")
	if not AuthGateway.is_authenticated() or AuthGateway.online_wallet.is_empty():
		status.text = "Online wallet unavailable. Reconnect or press Refresh. Local balances are not shown here."
		return
	var names := {"gold":"Gold","crystals":"Crystals","paid_moonstones":"Paid moonstones","gems":"Gems","ancient_coins":"Ancient coins","guild_tokens":"Guild tokens","event_tokens":"Event tokens"}
	var ids: Array = AuthGateway.online_currencies.keys()
	ids.sort()
	for id in ids:
		var amount := int(AuthGateway.online_currencies[id])
		if amount == 0 and not id in ["gold","crystals","paid_moonstones"]: continue
		wallet.add_child(UIFactory.chip(str(names.get(id,id))+"  "+UIFactory.number(amount),UITheme.GOLD if id=="gold" else UITheme.TEAL))
	var search: String = _online_layout.get_node("Filters/Search").text.strip_edges().to_lower()
	var filter: int = _online_layout.get_node("Filters/Category").selected
	var items: Array = AuthGateway.online_inventory.keys()
	items.sort()
	var shown := 0
	for id in items:
		var amount := int(AuthGateway.online_inventory[id])
		if amount<=0: continue
		var def: Dictionary = ContentDB.get_item(str(id))
		var category := str(def.get("category","other"))
		var card := str(id).begins_with("upgrade_")
		var group := 3 if card else (1 if category=="material" else (2 if category=="equipment" else 4))
		var name := str(def.get("name",str(id).replace("_"," ").capitalize()))
		if filter>0 and filter!=group: continue
		if not search.is_empty() and not (name+" "+str(id)).to_lower().contains(search): continue
		var entry: PanelContainer = preload("res://scenes/ui/components/online_inventory_item_row.tscn").instantiate()
		entry.get_node("Content/Name").text = name
		entry.get_node("Content/Category").text = "Upgrade card" if card else category.capitalize()
		entry.get_node("Content/Count").text = "x"+UIFactory.number(amount)
		entry.tooltip_text = str(def.get("description",name))
		_online_inventory_panel.add_child(entry)
		shown+=1
	status.text = "%d item types shown" % shown if shown>0 else "No items match this view."
