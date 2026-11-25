extends Control
class_name Act1MapAtlas
## Authored node-based Act I map. The panoramic pixel-art texture contains the
## environment and road; region labels, status markers and thumbnails are scene nodes.

signal region_selected(region_id: String)

const REGION_ORDER := [
	"castle_royal_gardens",
	"royal_gate",
	"willow_fields",
	"elderwood_grove",
	"forsaken_ruins",
	"ruined_tower",
]
const REGION_NAMES := [
	"Royal Gardens",
	"Royal Gate",
	"Willow Fields",
	"Elderwood Grove",
	"Forsaken Ruins",
	"Ruined Tower",
]
const REGION_NODES := [
	"Regions/RoyalGardens",
	"Regions/RoyalGate",
	"Regions/WillowFields",
	"Regions/ElderwoodGrove",
	"Regions/ForsakenRuins",
	"Regions/RuinedTower",
]

var selected_poi: Dictionary = {}
var selected_region_id := ""
var player_region_id := ""
var quest_region_id := ""


func _ready() -> void:
	# Positions are authored scene-node placements over the panorama, not a
	# generated terrain or map renderer.
	var map_positions := [
		Vector2(8, 250), Vector2(98, 188), Vector2(200, 222),
		Vector2(300, 122), Vector2(408, 164), Vector2(510, 70),
	]
	for i in REGION_NODES.size():
		var card := get_node_or_null(REGION_NODES[i]) as Control
		if card == null:
			continue
		card.position = map_positions[i]
		card.size = Vector2(94, 58)
		card.mouse_filter = Control.MOUSE_FILTER_STOP
		card.focus_mode = Control.FOCUS_ALL
		card.tooltip_text = "Select " + REGION_NAMES[i]
		card.gui_input.connect(_on_region_gui_input.bind(REGION_ORDER[i]))
		card.focus_entered.connect(set_selected_region.bind(REGION_ORDER[i]))
		var name_label := card.get_node_or_null("Name") as Label
		if name_label != null:
			name_label.position = Vector2(0, 20)
			name_label.size = Vector2(94, 20)
			name_label.add_theme_color_override("font_outline_color", Color("#211326"))
			name_label.add_theme_constant_override("outline_size", 4)
			name_label.add_theme_font_size_override("font_size", 11)
		for marker_name in ["CurrentMarker", "QuestMarker"]:
			var marker := card.get_node_or_null(marker_name) as Label
			if marker == null:
				continue
			marker.position = Vector2(0, 0 if marker_name == "CurrentMarker" else 40)
			marker.size = Vector2(94, 18)
			marker.add_theme_color_override("font_outline_color", Color("#211326"))
			marker.add_theme_constant_override("outline_size", 4)
	refresh_map()


func _on_region_gui_input(event: InputEvent, region_id: String) -> void:
	if event is InputEventMouseButton:
		var mouse_event := event as InputEventMouseButton
		if mouse_event.button_index == MOUSE_BUTTON_LEFT and mouse_event.pressed:
			var card := get_node_or_null(REGION_NODES[REGION_ORDER.find(region_id)]) as Control
			if card != null:
				card.accept_event()
			set_selected_region(region_id)


func set_selected_region(region_id: String) -> void:
	var idx := REGION_ORDER.find(region_id)
	if idx < 0:
		return
	selected_region_id = region_id
	selected_poi.clear()
	var selected_label := get_node_or_null("Header/SelectedPoint") as Label
	if selected_label != null:
		selected_label.text = "REGION  •  " + REGION_NAMES[idx].to_upper()
	for i in REGION_NODES.size():
		var card := get_node_or_null(REGION_NODES[i]) as Control
		if card == null:
			continue
		var name_label := card.get_node_or_null("Name") as Label
		if name_label != null:
			name_label.add_theme_color_override(
				"font_color",
				Color("#ffe0a6") if i == idx else Color("#fce6d1")
			)
	region_selected.emit(region_id)


func refresh_map() -> void:
	player_region_id = str(GameState.session_domain.player_region)
	var tracked := str(GameState.quest_domain.tracked_quest())
	quest_region_id = ""
	if not tracked.is_empty() and GameState.quest_domain.quest_state(tracked) == "active":
		var quest := ContentDB.get_quest(tracked)
		quest_region_id = str(quest.get("region", ""))
	for i in REGION_ORDER.size():
		var card := get_node_or_null(REGION_NODES[i]) as Control
		if card == null:
			continue
		var is_current: bool = str(REGION_ORDER[i]) == player_region_id
		var has_quest: bool = str(REGION_ORDER[i]) == quest_region_id
		var current_marker := card.get_node_or_null("CurrentMarker") as Control
		var quest_marker := card.get_node_or_null("QuestMarker") as Control
		if current_marker != null:
			current_marker.visible = is_current
		if quest_marker != null:
			quest_marker.visible = has_quest
	var status := get_node_or_null("Header/CurrentRegion") as Label
	if status != null:
		var idx := REGION_ORDER.find(player_region_id)
		status.text = "CURRENT REGION  •  " + (REGION_NAMES[idx].to_upper() if idx >= 0 else "OUTSIDE ACT I")


func set_selected_poi(poi: Dictionary) -> void:
	selected_poi = poi.duplicate(true) if typeof(poi) == TYPE_DICTIONARY else {}
	selected_region_id = ""
	var label := get_node_or_null("Header/SelectedPoint") as Label
	if label != null:
		label.text = "SELECTED  •  " + str(selected_poi.get("name", "NONE")).to_upper()
	for card_path in REGION_NODES:
		var card := get_node_or_null(card_path) as Control
		if card == null:
			continue
		var name_label := card.get_node_or_null("Name") as Label
		if name_label != null:
			name_label.add_theme_color_override("font_color", Color("#fce6d1"))
