extends VBoxContainer
const TRAVEL = preload("res://scripts/world/six_zone_reverie/fast_travel.gd")
var zone: Node2D
var selected := ""
var _refresh_elapsed := 0.0
const SCENERY := {
	"StandaloneZone01": "zone_01_royal_gardens.png",
	"StandaloneZone02": "zone_02_royal_gate.png",
	"StandaloneZone03": "zone_03_willow_fields.png",
	"StandaloneZone04": "zone_04_elderwood_grove.png",
	"StandaloneZone05": "zone_05_forsaken_ruins.png",
	"StandaloneZone06": "zone_06_ruined_tower.png",
}
const TRANSITION_PATH = "res://scenes/ui/components/fast_travel_transition.tscn"

func _ready() -> void:
	zone = TRAVEL.find_zone(self)
	$Confirm.pressed.connect(_confirm)
	if zone == null:
		return
	$CurrentLocation.text = "Current location: " + str(TRAVEL.NAMES.get(str(zone.name), zone.name))
	for button in $Body/Scroll/Destinations.get_children():
		var id := str(button.name)
		button.pressed.connect(_select.bind(id))
		if SCENERY.has(id):
			button.icon = load("res://assets/environment/six_zone_reverie/backgrounds/" + str(SCENERY[id]))
		if id == "StandaloneVillage":
			button.icon = load("res://assets/cinematics/gerald_story/fallen_guardian/01_Ashes of a Burning Village.png")
		button.tooltip_text = str(TRAVEL.NAMES[id])
	$Confirm.add_theme_stylebox_override("normal", UITheme.style(Color("#382c22"), UITheme.GOLD, 8, 1, 10))
	$Confirm.add_theme_stylebox_override("hover", UITheme.style(Color("#57432b"), UITheme.GOLD_BRIGHT, 8, 2, 10))
	$Confirm.add_theme_color_override("font_color", UITheme.GOLD_BRIGHT)
	resized.connect(_adapt_layout)
	get_viewport().size_changed.connect(_adapt_layout)
	_adapt_layout.call_deferred()
	_refresh_destinations()
	_show_preview(str(zone.name))


func _process(delta: float) -> void:
	if not is_instance_valid(zone) or not is_visible_in_tree():
		return
	_refresh_elapsed += delta
	if _refresh_elapsed < 0.35:
		return
	_refresh_elapsed = 0.0
	_refresh_destinations()
	if not selected.is_empty():
		var reason := TRAVEL.unavailable_reason(zone, selected)
		$Status.text = "Travel to " + str(TRAVEL.NAMES[selected]) + "?" if reason.is_empty() else reason
func _adapt_layout() -> void:
	var viewport_size := get_viewport_rect().size
	var physical := get_window().size
	var portrait := viewport_size.y > viewport_size.x
	var compact := physical.x < 1000 or physical.y < 600
	var body: BoxContainer = $Body
	body.vertical = portrait
	$Body/Preview.hide()
	$Body/Scroll/Destinations.columns = 2 if portrait or size.x < 700.0 else 4
	$Body/Scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	$Body/Scroll.size_flags_stretch_ratio = 1.0
	$Body/Preview.size_flags_stretch_ratio = 1.0
	for button in $Body/Scroll/Destinations.get_children():
		button.custom_minimum_size.y = 150.0 if portrait else (110.0 if compact else 165.0)
		button.add_theme_constant_override("icon_max_width", 150 if compact else 220)
		button.add_theme_font_size_override("font_size", 19 if portrait else (15 if compact else 16))
	$Confirm.custom_minimum_size.y = 82.0 if portrait else (66.0 if compact else 48.0)
	$Confirm.add_theme_font_size_override("font_size", 25 if portrait else (21 if compact else 15))
	$CurrentLocation.add_theme_font_size_override("font_size", 29 if compact else 18)
	for label in [$Hint, $Status, $Body/Preview/Content/Caption]:
		label.add_theme_font_size_override("font_size", 21 if compact else 13)
	$Body/Preview/Content/Title.add_theme_font_size_override("font_size", 28 if compact else 20)
	var screen := get_parent()
	while screen != null and not screen is OverlayScreen:
		screen = screen.get_parent()
	if screen != null:
		var header := screen.get_node("OverlayShell/Margin/Panel/Root/Header")
		header.get_node("Titles/Title").add_theme_font_size_override("font_size", 36 if compact else 27)
		header.get_node("Titles/Subtitle").add_theme_font_size_override("font_size", 19 if compact else 12)
		var close: Button = header.get_node("CloseButton")
		close.custom_minimum_size = Vector2(148, 66) if compact else Vector2(116, 40)
		close.add_theme_font_size_override("font_size", 22 if compact else 14)

func _show_preview(id: String) -> void:
	var artwork: TextureRect = $Body/Preview/Content/Artwork
	$Body/Preview/Content/Title.text = str(TRAVEL.NAMES[id])
	artwork.texture = null
	if id == str(zone.name):
		var minimap := zone.get_node_or_null("UI/HUD/Minimap") as Minimap
		if minimap != null and is_instance_valid(minimap._art_viewport):
			artwork.texture = minimap._art_viewport.get_texture()
		$Body/Preview/Content/Caption.text = "Current map | Choose a discovered destination."
	elif SCENERY.has(id):
		artwork.texture = load("res://assets/environment/six_zone_reverie/backgrounds/" + str(SCENERY[id]))
		$Body/Preview/Content/Caption.text = "Destination scenery | Free travel to the arrival point."
	else:
		$Body/Preview/Content/Caption.text = "Discovered destination | Free travel to the arrival point."
	artwork.visible = artwork.texture != null

func _refresh_destinations() -> void:
	for button in $Body/Scroll/Destinations.get_children():
		var id := str(button.name)
		var reason := TRAVEL.unavailable_reason(zone, id)
		button.disabled = not reason.is_empty()
		button.remove_theme_stylebox_override("normal")
		button.remove_theme_color_override("font_color")
		if id == selected and reason.is_empty():
			button.add_theme_stylebox_override("normal", UITheme.style(Color("#34263e"), UITheme.GOLD, 8, 2, 10))
			button.add_theme_color_override("font_color", UITheme.GOLD_BRIGHT)
		var order := TRAVEL.NAMES.keys().find(id)
		var label := "PROLOGUE" if order == 0 else "ZONE %02d" % order
		var status := "HERE" if id == str(zone.name) else ("LOCKED" if id not in TRAVEL.discovered() else ("READY" if reason.is_empty() else "UNAVAILABLE"))
		if id == selected and reason.is_empty():
			status = "SELECTED"
		button.text = label + "  |  " + status + "\n" + str(TRAVEL.NAMES[id])
		button.tooltip_text = str(TRAVEL.NAMES[id]) + ": " + (reason if not reason.is_empty() else "Teleport available")
		button.add_theme_color_override("icon_disabled_color", Color(0.47, 0.49, 0.60, 1.0) if id != str(zone.name) else Color.WHITE)
	$Confirm.disabled = selected.is_empty() or not TRAVEL.unavailable_reason(zone, selected).is_empty()

func _select(id: String) -> void:
	if not TRAVEL.unavailable_reason(zone, id).is_empty():
		return
	selected = id
	_show_preview(id)
	$Status.text = "Travel to " + str(TRAVEL.NAMES[id]) + "?"
	$Confirm.text = "Teleport to " + str(TRAVEL.NAMES[id])
	_refresh_destinations()

func _confirm() -> void:
	if TRAVEL.unavailable_reason(zone, selected).is_empty():
		var tree := get_tree()
		if tree.root.has_node("FastTravelTransition"):
			return
		var transition = load(TRANSITION_PATH).instantiate()
		tree.root.add_child(transition)
		transition.begin(zone, selected)
		return
	$Status.text = "Travel unavailable. " + TRAVEL.unavailable_reason(zone, selected)
	_refresh_destinations()
