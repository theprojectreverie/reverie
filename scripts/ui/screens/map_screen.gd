class_name MapScreen
extends OverlayScreen
## Functional world map: region name, player position, POIs, quest markers,
## and directional guidance to the tracked quest objective.

const MAP_LAYOUT_SCENE: PackedScene = preload("res://scenes/ui/components/map_screen_layout.tscn")

var _info_box: VBoxContainer
var _tracked_box: VBoxContainer
var _map_canvas: Control
var _region_label: Label
var _player_position_label: Label
var _selected_poi_id: String = ""
var _selected_detail_label: Label
var _live_refresh_elapsed: float = 0.0
var _last_map_region_id: String = ""
var _last_map_tracked_quest: String = ""
var _displayed_region_id: String = ""


func _init() -> void:
	screen_title = "World Map"
	screen_subtitle = "Current region, points of interest, and quest objectives"


func _build_content() -> void:
	var layout := MAP_LAYOUT_SCENE.instantiate() as HBoxContainer
	layout.size_flags_vertical = Control.SIZE_EXPAND_FILL
	content.add_child(layout)

	_region_label = layout.get_node("Left/RegionName") as Label
	_map_canvas = layout.get_node("Left/MapCanvas") as Control
	_last_map_region_id = str(GameState.session_domain.player_region)
	_last_map_tracked_quest = str(GameState.quest_domain.tracked_quest())
	_player_position_label = layout.get_node("Left/PlayerPosition") as Label
	_info_box = layout.get_node("Right/POIList") as VBoxContainer
	_tracked_box = layout.get_node("Right/TrackedQuestContent") as VBoxContainer

	var region: Dictionary = {}
	if GameState.session_domain.player_region != "":
		region = ContentDB.get_region(GameState.session_domain.player_region)
	var region_name := "Unknown"
	if not region.is_empty():
		region_name = str(region.get("name", GameState.session_domain.player_region))
	elif not str(GameState.session_domain.player_region).is_empty():
		region_name = str(GameState.session_domain.player_region).replace("_", " ").capitalize()
	_region_label.text = region_name
	_region_label.add_theme_color_override("font_color", UITheme.TEXT)

	# Use the live player node whenever the world is active; the saved
	# position is only a fallback for screens opened outside gameplay.
	var player_world: Vector2 = GameState.session_domain.player_position
	var live_player := get_tree().get_first_node_in_group("player")
	if live_player is Node2D:
		player_world = _current_player_region_position()
	var player_grid := IsoMath.world_to_grid(player_world)
	_player_position_label.text = "Player: (%.0f, %.0f)" % [player_grid.x, player_grid.y]
	_player_position_label.add_theme_color_override("font_color", UITheme.TEXT)

	_displayed_region_id = str(GameState.session_domain.player_region)
	if _map_canvas is Act1MapAtlas:
		var atlas := _map_canvas as Act1MapAtlas
		atlas.set_selected_region(_displayed_region_id)
		atlas.region_selected.connect(_on_atlas_region_selected)
	_populate_region_pois(region, player_world)
	_populate_tracked_quest(region, player_world)


func _on_atlas_region_selected(region_id: String) -> void:
	if region_id.is_empty():
		return
	var region: Dictionary = ContentDB.get_region(region_id)
	if region.is_empty():
		return
	_displayed_region_id = region_id
	_region_label.text = str(region.get("name", region_id.replace("_", " ").capitalize()))
	var player_world := _current_player_region_position()
	var is_current_region := region_id == str(GameState.session_domain.player_region)
	if is_current_region:
		var player_grid := IsoMath.world_to_grid(player_world)
		_player_position_label.text = "Player: (%.0f, %.0f)" % [player_grid.x, player_grid.y]
	else:
		_player_position_label.text = "Player: not in this region"
	_populate_region_pois(region, player_world)
	_populate_tracked_quest(region, player_world)


func _populate_region_pois(region: Dictionary, player_world: Vector2) -> void:
	if _info_box == null:
		return
	for child in _info_box.get_children():
		_info_box.remove_child(child)
		child.queue_free()
	_selected_detail_label = UIFactory.label("Select a point of interest to inspect it.", 11, UITheme.TEXT_DIM)
	_info_box.add_child(_selected_detail_label)
	_info_box.add_child(HSeparator.new())
	_selected_poi_id = ""
	var player_grid := IsoMath.world_to_grid(player_world)
	var is_current_region := _displayed_region_id == str(GameState.session_domain.player_region)
	var pois: Array = region.get("pois", [])
	var first := true
	for poi in pois:
		if typeof(poi) != TYPE_DICTIONARY:
			continue
		var grid: Variant = poi.get("grid", null)
		if typeof(grid) != TYPE_ARRAY or (grid as Array).size() != 2:
			continue
		var g: Array = grid
		var poi_id := str(poi.get("id", poi.get("name", "poi")))
		var poi_name := str(poi.get("name", poi.get("id", "POI")))
		var poi_type := str(poi.get("type", "landmark"))
		var poi_grid := Vector2(float(g[0]), float(g[1]))
		var distance_text := " - %.0f tiles" % player_grid.distance_to(poi_grid) if is_current_region else ""
		var button := Button.new()
		button.text = "%s  (%s)%s" % [poi_name, poi_type.capitalize(), distance_text]
		button.alignment = HORIZONTAL_ALIGNMENT_LEFT
		button.custom_minimum_size = Vector2(0, 30)
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.add_theme_font_size_override("font_size", 11)
		button.add_theme_color_override("font_color", UITheme.TEXT_DIM)
		button.pressed.connect(func() -> void: _select_poi(poi_id, poi, _current_player_region_position()))
		_info_box.add_child(button)
		if first:
			_select_poi(poi_id, poi, player_world, false)
			first = false
	if pois.is_empty():
		_info_box.add_child(UIFactory.label("No points of interest.", 11, UITheme.TEXT_DIM))


func _current_player_region_position() -> Vector2:
	# Legacy name retained for callers; this returns region-local coordinates.
	# POIs and quest destinations are authored in the active world's local frame.
	var live_player := get_tree().get_first_node_in_group("player") as Node2D
	if live_player != null:
		var world := get_tree().get_first_node_in_group("world") as Node2D
		if world != null and world.is_ancestor_of(live_player):
			return world.to_local(live_player.global_position)
		return live_player.global_position
	return GameState.session_domain.player_position


func _select_poi(poi_id: String, poi: Dictionary, player_world: Vector2 = GameState.session_domain.player_position, refresh: bool = true) -> void:
	_selected_poi_id = poi_id
	var grid: Array = poi.get("grid", [0, 0])
	var g := Vector2(float(grid[0]), float(grid[1])) if grid.size() == 2 else Vector2.ZERO
	var player_grid := IsoMath.world_to_grid(player_world)
	var is_current_region := _displayed_region_id == str(GameState.session_domain.player_region)
	if _selected_detail_label != null:
		if is_current_region:
			var dist_to: float = player_grid.distance_to(g)
			_selected_detail_label.text = "Selected: %s  (%.0f, %.0f)  - %.0f tiles" % [
				str(poi.get("name", poi_id)), g.x, g.y, dist_to
			]
		else:
			_selected_detail_label.text = "Selected: %s  (%.0f, %.0f)" % [
				str(poi.get("name", poi_id)), g.x, g.y
			]
		_selected_detail_label.add_theme_color_override("font_color", UITheme.GOLD_BRIGHT)
	if _map_canvas != null and _map_canvas.has_method("set_selected_poi"):
		_map_canvas.call("set_selected_poi", poi)
	elif refresh and _map_canvas != null and _map_canvas.has_method("refresh_map"):
		_map_canvas.refresh_map()


func _populate_tracked_quest(region: Dictionary, player_world: Vector2) -> void:
	if _tracked_box == null:
		return
	for child in _tracked_box.get_children():
		_tracked_box.remove_child(child)
		child.queue_free()
	var tracked: String = str(GameState.quest_domain.tracked_quest())
	if tracked.is_empty() or GameState.quest_domain.quest_state(tracked) != "active":
		_tracked_box.add_child(UIFactory.label("No quest tracked. Track one from the Quests screen.", 12, UITheme.TEXT_DIM))
		return

	var definition: Dictionary = ContentDB.get_quest(tracked)
	var step: Dictionary = GameState.quest_domain.quest_step(tracked)
	_tracked_box.add_child(UIFactory.label(str(definition.get("name", tracked)), 13, UITheme.TEXT))
	var resolver: QuestNavigationResolver = QuestNavigationResolver.shared()
	var game_screen := get_tree().get_first_node_in_group("game_screen")
	if game_screen != null and game_screen.get("quest_resolver") is QuestNavigationResolver:
		resolver = game_screen.get("quest_resolver") as QuestNavigationResolver
	var resolved := resolver.get_resolved_target(GameState.session_domain.player_region, player_world)
	var objective_text := str(resolved.get("step_text", step.get("text", "")))
	_tracked_box.add_child(UIFactory.label(objective_text, 11, UITheme.TEXT_DIM))
	if not bool(resolved.get("valid", false)):
		_tracked_box.add_child(UIFactory.label("Destination unavailable", 12, UITheme.TEXT_FAINT))
	elif not bool(resolved.get("same_frame", false)):
		var next_hop: Dictionary = resolved.get("next_hop", {})
		var route: Array = resolved.get("route", [])
		if not route.is_empty() and not next_hop.is_empty():
			var hop_label := str(next_hop.get("label", ""))
			if hop_label.is_empty():
				hop_label = "Travel to " + str(next_hop.get("to", resolved.get("target_region_id", "destination")))
			_tracked_box.add_child(UIFactory.label("Next: " + hop_label, 12, UITheme.TEAL))
		else:
			_tracked_box.add_child(UIFactory.label("No route to destination", 12, UITheme.TEXT_FAINT))
	elif str(resolved.get("status", "")) == QuestNavigationResolver.STATUS_UNREACHABLE:
		_tracked_box.add_child(UIFactory.label("Destination unreachable", 12, UITheme.TEXT_FAINT))
	else:
		var target_local: Variant = resolved.get("target_local_pos", null)
		var player_local: Variant = resolved.get("player_local_pos", null)
		var direction_value: Variant = resolved.get("direction", Vector2.ZERO)
		var arrow := _quest_arrow(direction_value)
		if typeof(target_local) == TYPE_VECTOR2 and typeof(player_local) == TYPE_VECTOR2:
			var target_grid := IsoMath.world_to_grid(target_local as Vector2)
			var player_grid := IsoMath.world_to_grid(player_local as Vector2)
			var tile_distance := player_grid.distance_to(target_grid)
			_tracked_box.add_child(UIFactory.label("%s  %.0f tiles" % [arrow, tile_distance], 12, UITheme.TEAL))


func _process(delta: float) -> void:
	# Keep the open map live while the player moves; opening the overlay must not
	# freeze the position marker or the coordinate readout at its initial value.
	_live_refresh_elapsed += delta
	if _live_refresh_elapsed < 0.15:
		return
	_live_refresh_elapsed = 0.0
	if _player_position_label == null or _map_canvas == null:
		return
	var player_world := _current_player_region_position()
	if _displayed_region_id == str(GameState.session_domain.player_region):
		var player_grid := IsoMath.world_to_grid(player_world)
		_player_position_label.text = "Player: (%.0f, %.0f)" % [player_grid.x, player_grid.y]
	# The Act I atlas is an authored node scene: one panorama texture plus
	# clickable region nodes and live player/quest markers. Refresh markers only
	# when the active region or tracked quest changes.
	var region_id := str(GameState.session_domain.player_region)
	var tracked_id := str(GameState.quest_domain.tracked_quest())
	var region_changed := region_id != _last_map_region_id
	var tracked_changed := tracked_id != _last_map_tracked_quest
	if region_changed:
		var previous_region_id := _last_map_region_id
		_last_map_region_id = region_id
		if _displayed_region_id == previous_region_id:
			if _map_canvas is Act1MapAtlas:
				(_map_canvas as Act1MapAtlas).set_selected_region(region_id)
			else:
				_on_atlas_region_selected(region_id)
		elif _map_canvas.has_method("refresh_map"):
			_map_canvas.refresh_map()
	if tracked_changed:
		_last_map_tracked_quest = tracked_id
		if _map_canvas.has_method("refresh_map"):
			_map_canvas.refresh_map()
		_populate_tracked_quest(ContentDB.get_region(_displayed_region_id), player_world)


func _refresh() -> void:
	if _map_canvas != null and _map_canvas.has_method("refresh_map"):
		_map_canvas.refresh_map()


func _quest_arrow(direction: Variant = null) -> String:
	var dir: Vector2 = direction if typeof(direction) == TYPE_VECTOR2 else GameState.quest_domain.direction_to_tracked()
	if dir.length_squared() < 0.0001:
		return "•"
	var angle := dir.angle()
	if angle < 0.0:
		angle += TAU
	var sector := int(round(angle / (PI * 0.25))) % 8
	var arrows := ["→", "↘", "↓", "↙", "←", "↖", "↑", "↗"]
	return arrows[sector]
