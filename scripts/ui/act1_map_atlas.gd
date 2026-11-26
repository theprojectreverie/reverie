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
	# Preserve the hand-authored panorama and region art. Layout responds to the panel size.
	for i in REGION_NODES.size():
		var card := get_node(REGION_NODES[i]) as Control
		card.mouse_filter = Control.MOUSE_FILTER_STOP
		card.focus_mode = Control.FOCUS_ALL
		card.z_index=1
		card.tooltip_text = "Explore " + REGION_NAMES[i]
		card.gui_input.connect(_on_region_gui_input.bind(REGION_ORDER[i]))
		card.focus_entered.connect(set_selected_region.bind(REGION_ORDER[i]))
		for child in card.get_children():
			child.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var key: String = str(REGION_NODES[i]).get_file()
		for suffix in ["Thumb", "ThumbLabel"]:
			get_node(key+suffix).mouse_filter = Control.MOUSE_FILTER_IGNORE
		card.get_node("Name").hide()
		var thumb_label := get_node(key+"ThumbLabel") as Label
		thumb_label.add_theme_color_override("font_outline_color", Color("#211326"))
		thumb_label.add_theme_constant_override("outline_size", 3)
	resized.connect(_layout_atlas)
	_layout_atlas()
	refresh_map()

func _layout_atlas() -> void:
	var w := size.x
	var h := size.y
	var narrow := w < 650.0
	var columns := 3 if narrow else 6
	var rows := 2 if narrow else 1
	var strip_h := 152.0 if narrow else 106.0
	var strip_top := h-strip_h-28.0
	$Background.size=size
	$Regions.size=size
	$Header.position=Vector2(14,8)
	$Header.size=Vector2(w-28,66)
	$Header/Title.add_theme_font_size_override("font_size",22)
	$Header/CurrentRegion.add_theme_font_size_override("font_size",13)
	$Header/SelectedPoint.add_theme_font_size_override("font_size",12)
	$Panorama.position=Vector2(12,76)
	$Panorama.size=Vector2(w-24,maxf(60,strip_top-82))
	$StripRule.position=Vector2(12,strip_top-3)
	$StripRule.size=Vector2(w-24,2)
	$RegionStrip.position=Vector2(12,strip_top)
	$RegionStrip.size=Vector2(w-24,strip_h)
	$Footer.position=Vector2(12,h-24)
	$Footer.size=Vector2(w-24,22)
	$Footer.add_theme_font_size_override("font_size",11)
	var cell_w: float=(w-24)/columns
	var cell_h: float=strip_h/rows
	for i in REGION_NODES.size():
		var card := get_node(REGION_NODES[i]) as Control
		var key: String = str(REGION_NODES[i]).get_file()
		var x: float=12+float(i%columns)*cell_w
		var y: float=strip_top+floorf(float(i)/columns)*cell_h
		card.position=Vector2(x,y)
		card.size=Vector2(cell_w,cell_h)
		var thumb := get_node(key+"Thumb") as TextureRect
		thumb.position=Vector2(x+4,y+4)
		thumb.size=Vector2(cell_w-8,cell_h-37)
		var title := get_node(key+"ThumbLabel") as Label
		title.position=Vector2(x+2,y+cell_h-33)
		title.size=Vector2(cell_w-4,16)
		title.add_theme_font_size_override("font_size",12 if cell_w>=105 else 10)
		for marker_name in ["CurrentMarker","QuestMarker"]:
			var marker := card.get_node(marker_name) as Label
			marker.position=Vector2(0 if marker_name=="CurrentMarker" else cell_w/2,cell_h-17)
			marker.size=Vector2(cell_w/2,15)
			marker.add_theme_font_size_override("font_size",10)
			marker.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER


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
	_update_strip_selection()
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
	var label := get_node_or_null("Header/SelectedPoint") as Label
	if label != null:
		label.text = "SELECTED  •  " + str(selected_poi.get("name", "NONE")).to_upper()
	_update_strip_selection()

func _update_strip_selection() -> void:
	for i in REGION_NODES.size():
		var key: String = str(REGION_NODES[i]).get_file()
		var label := get_node(key+"ThumbLabel") as Label
		var thumb := get_node(key+"Thumb") as TextureRect
		var chosen: bool=REGION_ORDER[i]==selected_region_id
		label.add_theme_color_override("font_color",UITheme.GOLD_BRIGHT if chosen else UITheme.TEXT_DIM)
		thumb.modulate=Color.WHITE if chosen else Color(0.77,0.79,0.86,1)
