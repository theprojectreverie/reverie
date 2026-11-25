extends Node

const MAP_SCENE: PackedScene = preload("res://scenes/ui/components/act1_map_atlas.tscn")
const REGION_PATHS := [
	"Regions/RoyalGardens",
	"Regions/RoyalGate",
	"Regions/WillowFields",
	"Regions/ElderwoodGrove",
	"Regions/ForsakenRuins",
	"Regions/RuinedTower",
]

func _ready() -> void:
	var atlas := MAP_SCENE.instantiate() as Act1MapAtlas
	add_child(atlas)
	await get_tree().process_frame
	var panorama := atlas.get_node("Panorama") as TextureRect
	assert(panorama != null and panorama.texture != null, "Authored panorama texture is loaded")
	assert(panorama.texture.get_width() == 128 and panorama.texture.get_height() == 64, "Panorama is a 2:1 pixel-art asset")
	assert(atlas.get_node_or_null("Road") == null and atlas.get_node_or_null("RoadHighlight") == null, "No code-drawn road nodes remain")
	for path in REGION_PATHS:
		var card := atlas.get_node(path) as Control
		assert(card != null, "Region node exists: " + path)
		assert(card.get_node("Name") is Label, "Region name is a scene Label: " + path)
		assert(card.get_node_or_null("ArtworkFrame") == null, "Old square card art nodes are removed: " + path)
	assert(atlas.get_node("RoyalGardensThumb") is TextureRect, "Region strip remains node-based")
	var selected_events: Array[String] = []
	atlas.region_selected.connect(func(region_id: String) -> void: selected_events.append(region_id))
	var grove_card := atlas.get_node("Regions/ElderwoodGrove") as Control
	grove_card.grab_focus()
	await get_tree().process_frame
	assert(atlas.selected_region_id == "elderwood_grove", "Keyboard focus selects the region node")
	assert((atlas.get_node("Header/SelectedPoint") as Label).text == "REGION  •  ELDERWOOD GROVE", "Region selection updates visible header")
	assert(selected_events == ["elderwood_grove"], "Region selection emits its scene signal")
	assert((atlas.get_node("Regions/ElderwoodGrove") as Control).mouse_filter == Control.MOUSE_FILTER_STOP, "Region nodes receive pointer input")
	var pointer_event := InputEventMouseButton.new()
	pointer_event.button_index = MOUSE_BUTTON_LEFT
	pointer_event.pressed = true
	atlas._on_region_gui_input(pointer_event, "willow_fields")
	assert(atlas.selected_region_id == "willow_fields", "Left mouse click selects a region")
	assert(selected_events == ["elderwood_grove", "willow_fields"], "Pointer selection emits the region signal")
	assert((atlas.get_node("Header/SelectedPoint") as Label).text == "REGION  •  WILLOW FIELDS", "Pointer selection updates the visible header")
	print("ACT1_MAP_ATLAS_PASS panorama=128x64 regions=6 keyboard=pass pointer=pass signal=region_selected road_art=authored")
	get_tree().quit()
