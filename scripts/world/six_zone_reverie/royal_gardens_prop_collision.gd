extends Node2D


func _ready() -> void:
	for node in find_children("FootprintCollision", "StaticBody2D", true, false):
		var body := node as StaticBody2D
		var prop := body.get_parent() as Sprite2D
		if not prop.is_visible_in_tree():
			body.collision_layer = 0
			continue
		_enable_prop_depth(prop)
		var shape := body.get_node("CollisionPolygon2D") as CollisionPolygon2D
		var bounds := Rect2(shape.polygon[0], Vector2.ZERO)
		for point in shape.polygon:
			bounds = bounds.expand(point)
		_anchor_depth_at_base(prop, prop.to_local(shape.to_global(bounds.get_center())))


func _enable_prop_depth(prop: Sprite2D) -> void:
	prop.z_index = 0
	var group := prop.get_parent() as Node2D
	while group != null and group != self:
		group.y_sort_enabled = true
		if group is Sprite2D:
			group.z_index = 0
		group = group.get_parent() as Node2D


func _anchor_depth_at_base(prop: Sprite2D, base: Vector2) -> void:
	# Keep the texture and child transforms in place while adjusting the sorting origin.
	prop.position += prop.transform.basis_xform(base)
	prop.offset -= base
	for child in prop.get_children():
		if child is Node2D:
			(child as Node2D).position -= base