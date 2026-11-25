from pathlib import Path
import shutil
p=Path(r'C:\Users\quoth\Documents\Default Project\project-fantasy')
f=p/'scripts/ui/minimap.gd';t=f.read_text(encoding='utf-8-sig');shutil.copy2(f,str(f)+'.before_six_zone_minimap')
t=t.replace('var _world: Node = null','''var _world: Node = null
var _six_zone: Node2D
var _zone_art: Array[Dictionary] = []
var _zone_bounds := Rect2()
var _overview := false''')
t=t.replace('\t_find_world()\n\tif marker_component', '\t_canvas.clip_contents = true\n\t_find_world()\n\tif marker_component',1)
t=t.replace('\t\t_world = get_tree().get_first_node_in_group("world")','''		var scene := get_tree().current_scene
		if scene is Node2D and str(scene.name).begins_with("StandaloneZone"):
			_world = scene
			if _six_zone != scene:
				_six_zone = scene
				_cache_zone_art()
		else:
			_world = get_tree().get_first_node_in_group("world")''',1)
t=t.replace('func _on_draw() -> void:\n\tif _collapsed:\n\t\treturn','''func _on_draw() -> void:
	if _collapsed:
		return
	if is_instance_valid(_six_zone):
		_draw_six_zone()
		return''',1)
t=t.replace('func _request_full_map() -> void:\n','''func _request_full_map() -> void:
	if is_instance_valid(_six_zone):
		_overview = not _overview
		_expand_button.text = "Near" if _overview else "Map"
		_canvas.queue_redraw()
		return
''',1)
t+='''

func _cache_zone_art() -> void:
	_zone_art.clear()
	_zone_bounds = Rect2()
	var roots: Array[Node] = []
	var terrain := _six_zone.get_node_or_null("Zone")
	if terrain != null:
		roots.append(terrain)
	for child in _six_zone.get_children():
		if child is Node2D and ("Road" in str(child.name) or "Connector" in str(child.name)):
			roots.append(child)
	for root in roots:
		for item in root.find_children("*", "Sprite2D", true, false):
			var sprite := item as Sprite2D
			if sprite.texture == null or not sprite.is_visible_in_tree():
				continue
			if sprite.is_in_group("world_minimap_npcs"):
				continue
			var bounds: Rect2 = sprite.global_transform * sprite.get_rect()
			if bounds.size.x <= 0.0 or bounds.size.y <= 0.0:
				continue
			_zone_art.append({"texture": sprite.texture, "rect": bounds, "z": sprite.z_index, "region": sprite.region_rect if sprite.region_enabled else Rect2()})
			_zone_bounds = bounds if _zone_bounds.size == Vector2.ZERO else _zone_bounds.merge(bounds)
	_zone_art.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		if a.z != b.z:
			return a.z < b.z
		return a.rect.end.y < b.rect.end.y)
	_expand_button.text = "Map"

func _draw_six_zone() -> void:
	var player := get_tree().get_first_node_in_group("player") as Node2D
	if player == null:
		return
	var viewport_rect := Rect2(Vector2(4, 25), _canvas.size - Vector2(8, 47))
	if viewport_rect.size.x <= 0 or viewport_rect.size.y <= 0:
		return
	var center := viewport_rect.get_center()
	var focus := player.global_position
	var factor := viewport_rect.size.x / 2400.0
	if _overview and _zone_bounds.size.x > 0 and _zone_bounds.size.y > 0:
		focus = _zone_bounds.get_center()
		factor = minf(viewport_rect.size.x / _zone_bounds.size.x, viewport_rect.size.y / _zone_bounds.size.y) * 0.96
	_canvas.draw_rect(Rect2(Vector2.ZERO, _canvas.size), Color("#161321"))
	var visible_world := Rect2(focus - viewport_rect.size / (2.0 * factor), viewport_rect.size / factor)
	for art in _zone_art:
		var r: Rect2 = art.rect
		if not visible_world.intersects(r):
			continue
		var dest := Rect2(center + (r.position - focus) * factor, r.size * factor)
		if art.region.size != Vector2.ZERO:
			_canvas.draw_texture_rect_region(art.texture, dest, art.region)
		else:
			_canvas.draw_texture_rect(art.texture, dest, false)
	for npc in get_tree().get_nodes_in_group("world_minimap_npcs"):
		if npc is Node2D and _six_zone.is_ancestor_of(npc):
			var point := center + (npc.global_position - focus) * factor
			if viewport_rect.has_point(point):
				_canvas.draw_circle(point, 5.0, Color("#17101c"))
				_canvas.draw_circle(point, 3.5, Color("#f1cd79"))
	var transfers := _six_zone.get_node_or_null("TransferPoints")
	if transfers != null:
		for marker in transfers.get_children():
			if marker is Marker2D and str(marker.name).begins_with("To"):
				var point := center + (marker.global_position - focus) * factor
				if viewport_rect.has_point(point):
					_canvas.draw_circle(point, 5.0, Color("#21162b"))
					_canvas.draw_arc(point, 4.0, 0, TAU, 16, Color("#e5b8ff"), 2.0)
	var point := center + (player.global_position - focus) * factor
	var direction := Vector2.from_angle(_player_facing)
	_canvas.draw_circle(point, 6.0, Color("#17101c"))
	_canvas.draw_colored_polygon(PackedVector2Array([point + direction * 7.0, point - direction * 4.0 + direction.orthogonal() * 4.0, point - direction * 4.0 - direction.orthogonal() * 4.0]), Color.WHITE)
'''
f.write_text(t,encoding='utf-8')
# Prevent old marker collector from treating standalone authored NPCs as legacy NPCs.
g=p/'scripts/ui/components/minimap_marker_component.gd';t=g.read_text(encoding='utf-8-sig');shutil.copy2(g,str(g)+'.before_six_zone_minimap')
t=t.replace('\tminimap._update_markers()','\tif not is_instance_valid(minimap._six_zone):\n\t\tminimap._update_markers()')
g.write_text(t,encoding='utf-8')
# Ensure first update finds current scene even if _ready ran before scene assignment.
print('Six-zone artwork minimap installed.')
