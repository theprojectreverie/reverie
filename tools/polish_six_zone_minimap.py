from pathlib import Path
import shutil
p=Path(r'C:\Users\quoth\Documents\Default Project\project-fantasy')
f=p/'scripts/ui/minimap.gd';t=f.read_text(encoding='utf-8-sig');shutil.copy2(f,str(f)+'.before_minimap_followup')
# Use the ancestor zone even during scene instantiation; do not rely on current_scene timing.
a=t.index('func _find_world()');b=t.index('func _update_markers()',a)
t=t[:a]+'''func _find_world() -> void:
	if not is_inside_tree():
		return
	var ancestor := get_parent()
	while ancestor != null:
		if ancestor is Node2D and str(ancestor.name).begins_with("StandaloneZone"):
			_world = ancestor
			if _six_zone != ancestor:
				_six_zone = ancestor
				_cache_zone_art()
			return
		ancestor = ancestor.get_parent()
	_six_zone = null
	_world = get_tree().get_first_node_in_group("world")


'''+t[b:]
# Keep the frame and buttons visible and anchored when collapsed.
t=t.replace('size = Vector2(60, 28)','size = Vector2(60, 28)\n\t\toffset_left = offset_right - 60.0\n\t\toffset_bottom = offset_top + 28.0',1)
t=t.replace('size = Vector2(MAP_SIZE, MAP_SIZE)\n\t\t_canvas.visible','size = Vector2(MAP_SIZE, MAP_SIZE)\n\t\toffset_left = offset_right - MAP_SIZE\n\t\toffset_bottom = offset_top + MAP_SIZE\n\t\t_canvas.visible',1)
# Transfer points are authored triggers; map their true positions when available.
t=t.replace('var point: Vector2 = center + (marker.global_position - focus) * factor','var transfer_position: Vector2 = marker.global_position\n\t\t\t\tfor child in marker.get_children():\n\t\t\t\t\tif child is Area2D:\n\t\t\t\t\t\ttransfer_position = child.global_position\n\t\t\t\t\t\tbreak\n\t\t\t\tvar point: Vector2 = center + (transfer_position - focus) * factor')
# Prevent terrain from spilling over legend and header with actual clipping control.
t=t.replace('var viewport_rect := Rect2(Vector2(4, 25), _canvas.size - Vector2(8, 47))','var viewport_rect := Rect2(Vector2.ZERO, _canvas.size)')
t=t.replace('_canvas.clip_contents = true','_canvas.clip_contents = true\n\t_canvas.offset_left = 4.0\n\t_canvas.offset_top = 25.0\n\t_canvas.offset_right = -4.0\n\t_canvas.offset_bottom = -22.0')
# Legacy minimap uses its original full-size canvas.
t=t.replace('\t\t\t\t_cache_zone_art()','\t\t\t\t_cache_zone_art()',1)
# Only use clipped inset for standalone minimap, legacy coordinates unchanged.
t=t.replace('\t_canvas.offset_left = 4.0\n\t_canvas.offset_top = 25.0\n\t_canvas.offset_right = -4.0\n\t_canvas.offset_bottom = -22.0\n','')
t=t.replace('func _cache_zone_art() -> void:\n','func _cache_zone_art() -> void:\n\t_canvas.offset_left = 4.0\n\t_canvas.offset_top = 25.0\n\t_canvas.offset_right = -4.0\n\t_canvas.offset_bottom = -22.0\n')
# Set legend to match actual markers.
t=t.replace('\t_expand_button.text = "Map"\n\nfunc _draw_six_zone','\t_expand_button.text = "Map"\n\t$Overlay/NpcDot.color = Color("#f1cd79")\n\t$Overlay/BossDot.color = Color("#e5b8ff")\n\t$Overlay/BossLabel.text = "Exit"\n\t$Overlay/PoiDot.hide()\n\t$Overlay/PoiLabel.hide()\n\t$Overlay/YouDot.color = Color.WHITE\n\nfunc _draw_six_zone')
f.write_text(t,encoding='utf-8')
print('Zone binding, clipping, exit tracking, legend and collapse corrected.')
