class_name Minimap
extends Control
## Compact live minimap showing terrain, player, NPCs, bosses and quest markers.

const MAP_SIZE := 224
const TILE_PX := 4.0
const VIEW_RADIUS := 26

var _collapsed: bool = false
var _expanded_size := Vector2(MAP_SIZE, MAP_SIZE)
var _expand_button: Button
var _collapse_button: Button
var _canvas: Control
var _overlay: Control
var _world: Node = null
var _six_zone: Node2D
# Compact positional draw commands: texture, bounds, destination, region,
# transform, z, tint, flip flags. Avoid a hash table for every map tile.
enum ArtField { TEXTURE, BOUNDS, DEST, REGION, TRANSFORM, Z, TINT, FLIPS }
var _zone_art: Array[Array] = []
var _zone_bounds := Rect2()
var _overview := true
var _art_viewport: SubViewport
var _art_canvas: Node2D
var _art_factor := 1.0
@onready var marker_component: MinimapMarkerComponent = get_node("MarkerData") as MinimapMarkerComponent
## Shared resolver injected by GameScreen through HUD; keeps compass, map and beacon aligned.
var quest_resolver: QuestNavigationResolver = null
var _player_grid: Vector2 = Vector2.ZERO
var _player_facing: float = 0.0
var _npc_markers: Array:
	get: return marker_component.npc_markers if marker_component != null else []
var _boss_markers: Array:
	get: return marker_component.boss_markers if marker_component != null else []
var _interactable_markers: Array:
	get: return marker_component.interactable_markers if marker_component != null else []
var _quest_marker: Vector2:
	get: return marker_component.quest_marker if marker_component != null else Vector2.ZERO
var _has_quest_marker: bool:
	get: return marker_component.has_quest_marker if marker_component != null else false


func _ready() -> void:
	custom_minimum_size = Vector2(MAP_SIZE, MAP_SIZE)
	size = Vector2(MAP_SIZE, MAP_SIZE)
	mouse_filter = Control.MOUSE_FILTER_STOP
	_canvas = get_node("MapCanvas") as Control
	_overlay = get_node_or_null("Overlay") as Control
	_expand_button = get_node("ExpandButton") as Button
	_collapse_button = get_node("CollapseButton") as Button
	_canvas.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if _overlay:
		_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_canvas.draw.connect(_on_draw)
	resized.connect(_layout_top_controls)
	_expand_button.pressed.connect(_request_full_map)
	_collapse_button.pressed.connect(_toggle_collapse)
	$TravelButton.pressed.connect(_open_fast_travel)
	_canvas.clip_contents = true
	_find_world()
	GraphicsSettings.quality_changed.connect(_on_graphics_quality_changed)
	if marker_component != null:
		marker_component.bind(self)


func _find_world() -> void:
	if not is_inside_tree():
		return
	var ancestor := get_parent()
	while ancestor != null:
		if ancestor is Node2D and (str(ancestor.name).begins_with("StandaloneZone") or ancestor.name == "StandaloneVillage"):
			_world = ancestor
			if _six_zone != ancestor:
				_six_zone = ancestor
				_cache_zone_art()
			return
		ancestor = ancestor.get_parent()
	_six_zone = null
	_world = get_tree().get_first_node_in_group("world")


func _update_markers() -> void:
	if marker_component != null:
		marker_component.update_markers(self, _world, quest_resolver)
		_world = marker_component.active_world


func _on_draw() -> void:
	if _collapsed:
		return
	if is_instance_valid(_six_zone):
		_draw_six_zone()
		return
	var center := Vector2(MAP_SIZE * 0.5, MAP_SIZE * 0.5)
	var player_pos := _player_grid

	# Draw terrain.
	for dy in range(-VIEW_RADIUS, VIEW_RADIUS + 1):
		for dx in range(-VIEW_RADIUS, VIEW_RADIUS + 1):
			var grid_pos := player_pos + Vector2(dx, dy)
			var world_pos := IsoMath.grid_to_world(grid_pos.x, grid_pos.y)
			var is_water := false
			if _world != null and is_instance_valid(_world) and _world.has_method("is_water_world"):
				is_water = bool(_world.is_water_world(world_pos))
			var px := center.x + dx * TILE_PX
			var py := center.y + dy * TILE_PX
			var tile_seed := absi(int(grid_pos.x) * 73856093 ^ int(grid_pos.y) * 19349663)
			var variation := float(tile_seed % 9) * 0.018
			var color := Color(0.075 + variation, 0.13 + variation, 0.085 + variation * 0.55) if not is_water else Color(0.025, 0.105 + variation, 0.19 + variation)
			var tile_rect := Rect2(px - TILE_PX * 0.5, py - TILE_PX * 0.5, TILE_PX, TILE_PX)
			_canvas.draw_rect(tile_rect, color)
			if not is_water and _world != null and is_instance_valid(_world) and _world.has_method("is_water_world"):
				var near_water := false
				for water_offset in [Vector2(1, 0), Vector2(-1, 0), Vector2(0, 1), Vector2(0, -1)]:
					var adjacent_world := IsoMath.grid_to_world(grid_pos.x + water_offset.x, grid_pos.y + water_offset.y)
					if bool(_world.is_water_world(adjacent_world)):
						near_water = true
						break
				if near_water:
					_canvas.draw_rect(tile_rect, Color(0.30, 0.64, 0.68, 0.45), false, 0.65)

	# Draw authored points of interest.
	var region: Dictionary = {}
	if GameState.session_domain.player_region != "":
		region = ContentDB.get_region(GameState.session_domain.player_region)
	for poi in region.get("pois", []):
		if typeof(poi) != TYPE_DICTIONARY:
			continue
		var grid: Variant = poi.get("grid", null)
		if typeof(grid) != TYPE_ARRAY or (grid as Array).size() != 2:
			continue
		var coordinates: Array = grid
		var poi_grid := Vector2(float(coordinates[0]), float(coordinates[1]))
		var offset := poi_grid - player_pos
		if abs(offset.x) > VIEW_RADIUS or abs(offset.y) > VIEW_RADIUS:
			continue
		var poi_center := center + offset * TILE_PX
		var poi_type := str(poi.get("type", ""))
		var poi_color := Color("#e7c36b")
		match poi_type:
			"boss":
				poi_color = Color("#ff6878")
				_canvas.draw_colored_polygon(PackedVector2Array([poi_center + Vector2(0, -5), poi_center + Vector2(5, 0), poi_center + Vector2(0, 5), poi_center + Vector2(-5, 0)]), poi_color)
			"village":
				poi_color = Color("#f0d27c")
				_canvas.draw_circle(poi_center, 4.0, poi_color)
				_canvas.draw_circle(poi_center, 2.0, Color("#59452d"))
			"ruin", "dungeon":
				poi_color = Color("#bd91f5")
				_canvas.draw_rect(Rect2(poi_center - Vector2(3.5, 3.5), Vector2(7, 7)), poi_color)
			_:
				_canvas.draw_circle(poi_center, 3.0, poi_color)
		_canvas.draw_arc(poi_center, 6.0, 0.0, TAU, 16, Color(poi_color.r, poi_color.g, poi_color.b, 0.55), 1.0)

	# Draw NPCs and quest givers.
	for marker in _npc_markers:
		var offset: Vector2 = marker.pos - player_pos
		if abs(offset.x) > VIEW_RADIUS or abs(offset.y) > VIEW_RADIUS:
			continue
		var point := center + offset * TILE_PX
		var quest_status := str(marker.get("quest", ""))
		if quest_status == "available" or quest_status == "ready":
			_canvas.draw_circle(point, 4.5, Color(marker.color.r, marker.color.g, marker.color.b, 0.22))
			_canvas.draw_colored_polygon(PackedVector2Array([
				point + Vector2(0, -3.5), point + Vector2(3.5, 0),
				point + Vector2(0, 3.5), point + Vector2(-3.5, 0)
			]), marker.color)
		else:
			_canvas.draw_circle(point, 2.0, marker.color)

	# Draw bosses.
	for marker in _boss_markers:
		var offset: Vector2 = marker.pos - player_pos
		if abs(offset.x) > VIEW_RADIUS or abs(offset.y) > VIEW_RADIUS:
			continue
		var point := center + offset * TILE_PX
		_canvas.draw_circle(point, 3.0, marker.color)
		_canvas.draw_arc(point, 5.0, 0, TAU, 12, marker.color, 1.0)

	# Draw gathering objects, shrines and lore markers.
	for marker in _interactable_markers:
		var offset: Vector2 = marker.pos - player_pos
		if abs(offset.x) > VIEW_RADIUS or abs(offset.y) > VIEW_RADIUS:
			continue
		var point := center + offset * TILE_PX
		var marker_color := Color("#79e6d5")
		var kind := str(marker.get("kind", ""))
		if kind.contains("crystal"):
			marker_color = Color("#bd91ff")
		elif kind.contains("berry") or kind.contains("herb") or kind.contains("bloom"):
			marker_color = Color("#91e6a2")
		elif kind.contains("shrine"):
			marker_color = Color("#f0d27c")
		_canvas.draw_circle(point, 4.5, Color(marker_color.r, marker_color.g, marker_color.b, 0.18))
		_canvas.draw_colored_polygon(PackedVector2Array([
			point + Vector2(0, -3.2), point + Vector2(3.2, 0),
			point + Vector2(0, 3.2), point + Vector2(-3.2, 0)
		]), marker_color)

	# Draw the tracked objective, with an edge arrow when it is off-screen.
	if _has_quest_marker:
		var offset := _quest_marker - player_pos
		if abs(offset.x) <= VIEW_RADIUS and abs(offset.y) <= VIEW_RADIUS:
			var marker_center := center + offset * TILE_PX
			var pulse := 0.5 + 0.5 * sin(float(Time.get_ticks_msec()) * 0.004)
			_canvas.draw_circle(marker_center, 7.0 + pulse * 3.0, Color(1.0, 0.78, 0.12, 0.10 + pulse * 0.10))
			_canvas.draw_arc(marker_center, 8.0 + pulse * 3.0, 0.0, TAU, 24, Color(1.0, 0.84, 0.25, 0.55 + pulse * 0.30), 1.2)
			_canvas.draw_colored_polygon(PackedVector2Array([
				marker_center + Vector2(0, -5), marker_center + Vector2(4, 0),
				marker_center + Vector2(0, 5), marker_center + Vector2(-4, 0)
			]), Color(1.0, 0.90, 0.38))
		else:
			var direction := Vector2(offset.x, offset.y)
			if direction.length_squared() > 0.001:
				direction = direction.normalized()
				var edge_distance := float(VIEW_RADIUS) * TILE_PX - 12.0
				var edge := center + direction * edge_distance
				var side := Vector2(-direction.y, direction.x)
				var arrow_points := PackedVector2Array([
					edge + direction * 8.0,
					edge - direction * 7.0 + side * 5.5,
					edge - direction * 7.0 - side * 5.5
				])
				_canvas.draw_circle(edge, 8.0, Color(1.0, 0.78, 0.12, 0.16))
				_canvas.draw_colored_polygon(arrow_points, Color(1.0, 0.82, 0.16))

	# Draw the player at the center and indicate facing.
	var player_color := Color(0.3, 0.8, 1.0)
	_canvas.draw_circle(center, 6.0, Color(player_color.r, player_color.g, player_color.b, 0.18))
	_canvas.draw_circle(center, 3.5, player_color)
	var facing := Vector2(cos(_player_facing), sin(_player_facing))
	var facing_side := Vector2(-facing.y, facing.x)
	var player_tip := center + facing * 10.0
	_canvas.draw_colored_polygon(PackedVector2Array([
		player_tip,
		center - facing * 4.0 + facing_side * 4.0,
		center - facing * 4.0 - facing_side * 4.0
	]), Color.WHITE)


func set_layout_rect(top: float, right: float, requested_size: float) -> void:
	# The authored legend requires at least 224 logical pixels.
	var side := maxf(float(MAP_SIZE), requested_size)
	_expanded_size = Vector2(side, side)
	var dimensions := Vector2(60, 28) if _collapsed else _expanded_size
	custom_minimum_size = dimensions
	size = dimensions
	position = Vector2(get_parent_area_size().x + right - dimensions.x, top)
	_layout_top_controls()

func _toggle_collapse() -> void:
	var right := offset_right
	var top := offset_top
	if not _collapsed:
		_expanded_size = size
	_collapsed = not _collapsed
	if _collapsed:
		custom_minimum_size = Vector2(60, 28)
		offset_left = offset_right - 60.0
		offset_bottom = offset_top + 28.0
		size = Vector2(60, 28)
		_canvas.visible = false
		if _overlay:
			_overlay.visible = false
		_expand_button.visible = false
		$TravelButton.hide()
		# Keep the restore control inside the collapsed chip. Previously it kept
		# its expanded-map X offset (156 px), leaving the button outside the
		# 60 px control and making the minimap impossible to reopen.
		_collapse_button.position = Vector2(36.0, 2.0)
		_collapse_button.size = Vector2(22.0, 24.0)
		_collapse_button.text = "+"
	else:
		custom_minimum_size = _expanded_size
		size = _expanded_size
		offset_left = offset_right - _expanded_size.x
		offset_bottom = offset_top + _expanded_size.y
		_canvas.visible = true
		if _overlay:
			_overlay.visible = true
		_expand_button.visible = true
		$TravelButton.visible = is_instance_valid(_six_zone)
		_collapse_button.position = Vector2(size.x - 68.0, 4.0)
		_collapse_button.size = Vector2(20.0, 20.0)
		_collapse_button.text = "-"
	set_layout_rect(top, right, _expanded_size.x)
	_find_world()


func _request_full_map() -> void:
	if is_instance_valid(_six_zone):
		_overview = not _overview
		_expand_button.text = "Near" if _overview else "Map"
		_canvas.queue_redraw()
		return
	var tree := get_tree()
	if tree:
		var game_screen = tree.get_first_node_in_group("game_screen")
		if game_screen and game_screen.has_method("open_screen"):
			game_screen.open_screen("map")


func _cache_zone_art() -> void:
	_canvas.offset_left = 4.0
	_canvas.offset_top = 25.0
	_canvas.offset_right = -4.0
	_canvas.offset_bottom = -22.0
	_zone_art.clear()
	_zone_bounds = Rect2()
	_overview = true
	for child in _six_zone.get_children():
		if child is Node2D:
			_collect_map_art(child, 0, Color.WHITE)
	_zone_art.sort_custom(func(a: Array, b: Array) -> bool:
		if a[ArtField.Z] != b[ArtField.Z]:
			return a[ArtField.Z] < b[ArtField.Z]
		return a[ArtField.BOUNDS].end.y < b[ArtField.BOUNDS].end.y)
	_build_cached_preview()
	_expand_button.text = "Near"
	$TravelButton.show()
	$Overlay/NpcDot.color = Color("#f1cd79")
	$Overlay/BossDot.color = Color("#ff8299")
	$Overlay/BossLabel.text = "Boss"
	$Overlay/PoiDot.color = Color("#e5b8ff")
	$Overlay/PoiLabel.text = "Exit"
	$Overlay/PoiDot.show()
	$Overlay/PoiLabel.show()
	$Overlay/WaystoneDot.show()
	$Overlay/WaystoneLabel.show()
	$Overlay/YouDot.color = Color.WHITE

func _collect_map_art(node: Node, inherited_z: int, tint: Color) -> void:
	if node is CanvasLayer or node is Control or node is Camera2D or node is CharacterBody2D or node is Interactable:
		return
	var lower := str(node.name).to_lower()
	if "fog" in lower or "background" in lower or "camera" in lower or "revienna" in lower or "light" in lower or "transferpoints" in lower or "fairy" in lower:
		return
	var z := inherited_z
	var color := tint
	if node is CanvasItem:
		if not node.is_visible_in_tree():
			return
		z = inherited_z + node.z_index if node.z_as_relative else node.z_index
		color *= node.modulate
	if node is Sprite2D:
		var sprite := node as Sprite2D
		if sprite.texture != null:
			var local_rect := sprite.get_rect()
			var source := sprite.region_rect if sprite.region_enabled else Rect2(Vector2.ZERO, sprite.texture.get_size())
			_add_map_art(sprite.texture, local_rect, source, sprite.global_transform, z, color * sprite.self_modulate, sprite.flip_h, sprite.flip_v)
	if node is TileMapLayer:
		var layer := node as TileMapLayer
		var tileset := layer.tile_set
		if tileset != null:
			# Identical atlas tiles share immutable metadata. Cache per layer so
			# alternative tiles, flip flags and texture origins stay exact.
			var metadata: Dictionary = {}
			var layer_transform := layer.global_transform
			var layer_tint := color * layer.self_modulate
			for cell in layer.get_used_cells():
				var source_id := layer.get_cell_source_id(cell)
				var coords := layer.get_cell_atlas_coords(cell)
				var key := Vector4i(source_id, coords.x, coords.y, layer.get_cell_alternative_tile(cell))
				if not metadata.has(key):
					if not tileset.has_source(source_id):
						metadata[key] = []
						continue
					var atlas := tileset.get_source(source_id) as TileSetAtlasSource
					if atlas == null or atlas.texture == null or not atlas.has_tile(coords):
						metadata[key] = []
						continue
					var region := Rect2(atlas.get_tile_texture_region(coords))
					var tile_data := layer.get_cell_tile_data(cell)
					var origin := Vector2(tile_data.texture_origin) if tile_data != null else Vector2.ZERO
					metadata[key] = [atlas.texture, region, origin - region.size * 0.5, z + (tile_data.z_index if tile_data != null else 0), tile_data.flip_h if tile_data != null else false, tile_data.flip_v if tile_data != null else false]
				var cached: Array = metadata[key]
				if cached.is_empty():
					continue
				var region: Rect2 = cached[1]
				var local_rect := Rect2(layer.map_to_local(cell) + (cached[2] as Vector2), region.size)
				_add_map_art(cached[0], local_rect, region, layer_transform, cached[3], layer_tint, cached[4], cached[5])
	for child in node.get_children():
		_collect_map_art(child, z, color)

func _add_map_art(texture: Texture2D, local_rect: Rect2, source: Rect2, transform: Transform2D, z: int, tint: Color, flip_h: bool, flip_v: bool) -> void:
	var bounds := transform * local_rect
	if bounds.size.x <= 0 or bounds.size.y <= 0:
		return
	_zone_art.append([texture, bounds, local_rect, source, transform, z, tint, int(flip_h) | (int(flip_v) << 1)])
	_zone_bounds = bounds if _zone_bounds.size == Vector2.ZERO else _zone_bounds.merge(bounds)

func _on_graphics_quality_changed() -> void:
	if is_instance_valid(_six_zone) and is_instance_valid(_art_viewport):
		_build_cached_preview()
		_canvas.queue_redraw()


func _build_cached_preview() -> void:
	if is_instance_valid(_art_viewport):
		remove_child(_art_viewport)
		_art_viewport.queue_free()
		_art_viewport = null
	if _zone_bounds.size.x <= 0 or _zone_bounds.size.y <= 0:
		return
	var preview_limit := GraphicsSettings.minimap_preview_limit(TouchInput.using_touch or OS.has_feature("mobile"))
	_art_factor = minf(preview_limit / _zone_bounds.size.x, preview_limit / _zone_bounds.size.y)
	_art_viewport = SubViewport.new()
	_art_viewport.name = "CachedMapArtwork"
	_art_viewport.size = Vector2i(ceil(_zone_bounds.size.x * _art_factor), ceil(_zone_bounds.size.y * _art_factor))
	_art_viewport.transparent_bg = true
	_art_viewport.disable_3d = true
	_art_viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
	_art_viewport.world_2d = World2D.new()
	add_child(_art_viewport)
	_art_canvas = Node2D.new()
	_art_canvas.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	_art_viewport.add_child(_art_canvas)
	_art_canvas.draw.connect(_draw_cached_preview)

func _draw_cached_preview() -> void:
	var world_to_texture := Transform2D(Vector2(_art_factor, 0), Vector2(0, _art_factor), -_zone_bounds.position * _art_factor)
	for art in _zone_art:
		_art_canvas.draw_set_transform_matrix(world_to_texture * art[ArtField.TRANSFORM])
		var dest: Rect2 = art[ArtField.DEST]
		var flips: int = art[ArtField.FLIPS]
		if flips & 1:
			dest.size.x = -dest.size.x
		if flips & 2:
			dest.size.y = -dest.size.y
		_art_canvas.draw_texture_rect_region(art[ArtField.TEXTURE], dest, art[ArtField.REGION], art[ArtField.TINT])
	_art_canvas.draw_set_transform_matrix(Transform2D.IDENTITY)

func _draw_six_zone() -> void:
	var player := _six_zone.get("checkpoint_player") as Node2D
	if player == null:
		return
	var viewport_rect := Rect2(Vector2.ZERO, _canvas.size)
	if viewport_rect.size.x <= 0 or viewport_rect.size.y <= 0:
		return
	var center := viewport_rect.get_center()
	var focus := player.global_position
	var factor := viewport_rect.size.x / 2400.0
	if _overview and _zone_bounds.size.x > 0 and _zone_bounds.size.y > 0:
		focus = _zone_bounds.get_center()
		factor = minf(viewport_rect.size.x / _zone_bounds.size.x, viewport_rect.size.y / _zone_bounds.size.y) * 0.96
	_canvas.draw_rect(Rect2(Vector2.ZERO, _canvas.size), Color("#161321"))
	if is_instance_valid(_art_viewport):
		var dest := Rect2(center + (_zone_bounds.position - focus) * factor, _zone_bounds.size * factor)
		_canvas.draw_texture_rect(_art_viewport.get_texture(), dest, false)
	for npc in get_tree().get_nodes_in_group("world_minimap_npcs"):
		if npc is Node2D and _six_zone.is_ancestor_of(npc):
			var point: Vector2 = center + (npc.global_position - focus) * factor
			if viewport_rect.has_point(point):
				_canvas.draw_circle(point, 5.0, Color("#17101c"))
				_canvas.draw_circle(point, 3.5, Color("#f1cd79"))
	for target in get_tree().get_nodes_in_group("world_minimap_monsters"):
		if target is Node2D and _six_zone.is_ancestor_of(target) and target.visible:
			if "defeated" in target and target.defeated:
				continue
			var location: Vector2 = center + (target.global_position - focus) * factor
			if viewport_rect.has_point(location):
				var boss: bool = "is_boss" in target and target.is_boss
				_canvas.draw_circle(location, 3.5 if boss else 2.0, Color("#ff8299") if boss else Color("#d68e59"))
	var revienna := _six_zone.get_node_or_null("ReviennaEncounter") as Interactable
	var in_expedition := not MultiplayerGateway.standalone_expedition_id.is_empty()
	var finale_pending := not in_expedition and bool(GameState.quest_domain.flags.get("ravienna_ending_pending", false)) and not bool(GameState.quest_domain.flags.get("ravienna_ending_seen", false))
	if revienna != null and (finale_pending or (not bool(revienna.get("defeated")) if in_expedition else not bool(GameState.quest_domain.flags.get("revienna_defeated", false)))):
		var location: Vector2 = center + (revienna.global_position - focus) * factor
		if viewport_rect.has_point(location):
			_canvas.draw_circle(location, 5.0, Color("#261021"))
			_canvas.draw_circle(location, 3.5, Color("#f1cd79") if finale_pending else Color("#ff8299"))
	for waypoint in get_tree().get_nodes_in_group("world_minimap_waypoints"):
		if waypoint is Node2D and _six_zone.is_ancestor_of(waypoint) and waypoint.visible:
			var location: Vector2 = center + (waypoint.global_position - focus) * factor
			if viewport_rect.has_point(location):
				_canvas.draw_circle(location, 5.0, Color("#17101c"))
				_canvas.draw_circle(location, 3.0, Color("#7fe3e0"))
	var transfers := _six_zone.get_node_or_null("TransferPoints")
	if transfers != null:
		for marker in transfers.get_children():
			if marker is Marker2D and str(marker.name).begins_with("To"):
				var transfer_position: Vector2 = marker.global_position
				for child in marker.get_children():
					if child is Area2D:
						transfer_position = child.global_position
						break
				var point: Vector2 = center + (transfer_position - focus) * factor
				if viewport_rect.has_point(point):
					_canvas.draw_circle(point, 5.0, Color("#21162b"))
					_canvas.draw_arc(point, 4.0, 0, TAU, 16, Color("#e5b8ff"), 2.0)
	# Both map modes use the same live chapter objective as the HUD.
	var guidance: Dictionary = _six_zone.get_meta("chapter_navigation",{})
	if bool(guidance.get("valid",false)) and not bool(player.get("network_recovery_paused")):
		var objective := center + (Vector2(guidance.position) - focus) * factor
		var inset := viewport_rect.grow(-10.0)
		var shown := objective
		if not inset.has_point(objective):
			var direction_to_target := (objective-center).normalized()
			var extent := inset.size*0.5
			var reach := minf(extent.x/maxf(absf(direction_to_target.x),0.001),extent.y/maxf(absf(direction_to_target.y),0.001))
			shown = center + direction_to_target*reach
		_canvas.draw_circle(shown,7.0,Color("#17101c"))
		_canvas.draw_colored_polygon(PackedVector2Array([shown+Vector2(0,-6),shown+Vector2(6,0),shown+Vector2(0,6),shown+Vector2(-6,0)]),Color("#7fe3e0") if not MultiplayerGateway.standalone_expedition_id.is_empty() else Color("#ffe08a"))
	var point := center + (player.global_position - focus) * factor
	var direction := Vector2.from_angle(_player_facing)
	if "facing_direction" in player and player.facing_direction.length_squared() > 0.01:
		direction = player.facing_direction.normalized()
	_canvas.draw_circle(point, 6.0, Color("#17101c"))
	_canvas.draw_colored_polygon(PackedVector2Array([point + direction * 7.0, point - direction * 4.0 + direction.orthogonal() * 4.0, point - direction * 4.0 - direction.orthogonal() * 4.0]), Color.WHITE)

func _open_fast_travel() -> void:
	if is_instance_valid(_six_zone):
		var binding := _six_zone.get_node_or_null("ZoneUIBinding")
		if binding != null:
			binding._open_screen("map")

func _layout_top_controls() -> void:
	if not is_instance_valid(_collapse_button) or not is_instance_valid(_expand_button):
		return
	if _collapsed:
		_collapse_button.position = Vector2(size.x - 24.0, 2.0)
	else:
		_collapse_button.position = Vector2(size.x - 68.0, 4.0)
		_expand_button.position = Vector2(size.x - 44.0, 4.0)
