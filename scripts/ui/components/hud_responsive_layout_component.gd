class_name HUDResponsiveLayoutComponent
extends Node
## Owns viewport-driven HUD layout adaptations for compact portrait and landscape.

var hud: HUD


func bind(owner_hud: HUD) -> void:
	hud = owner_hud


func apply(viewport_size: Vector2 = Vector2.ZERO) -> void:
	if hud == null or not hud.is_inside_tree():
		return
	if viewport_size == Vector2.ZERO:
		viewport_size = hud.get_viewport_rect().size
	var compact_portrait := viewport_size.x / maxf(1.0, viewport_size.y) < 0.85

	var party_panel := hud.get_node_or_null("PartyPanel") as Control
	if party_panel != null:
		party_panel.visible = not compact_portrait

	if hud._hint_label != null:
		hud._hint_label.visible = not compact_portrait

	if hud._minimap != null:
		hud._minimap.set_layout_rect(90.0, -18.0 if compact_portrait else -20.0, 224.0)

	var prompt_center := hud.get_node_or_null("PromptCenter") as Control
	if prompt_center != null:
		if compact_portrait:
			prompt_center.offset_top = -viewport_size.y * 0.62
			prompt_center.offset_bottom = -viewport_size.y * 0.54
		else:
			prompt_center.offset_top = -104.0
			prompt_center.offset_bottom = -34.0
	if TouchInput.using_touch:
		_apply_touch_layout(viewport_size, compact_portrait)

func _apply_touch_layout(viewport_size: Vector2, portrait: bool) -> void:
	var unit := clampf((viewport_size.x if portrait else viewport_size.y) / (390.0 if portrait else 420.0), 1.0, 3.4)
	var margin := 12.0 * unit
	var height := 44.0 * unit
	var width := 70.0 * unit
	var combat := hud._touch_combat
	if combat != null:
		combat.offset_left = -(width * 3.0 + margin * 2.0 + 16.0)
		combat.offset_right = -margin
		combat.offset_top = -height - margin
		combat.offset_bottom = -margin
		for child in combat.get_children():
			var button := child as Button
			button.custom_minimum_size = Vector2(width, height)
			button.add_theme_font_size_override("font_size", roundi(12.0 * unit))
	var stack := hud.get_node_or_null("ActionStack") as VBoxContainer
	if stack != null:
		var nav_height := 38.0 * unit
		stack.offset_left = -margin - 108.0 * unit - (0.0 if portrait else 244.0)
		stack.offset_right = -margin - (0.0 if portrait else 244.0)
		stack.offset_bottom = -height - margin * 2.0
		stack.offset_top = stack.offset_bottom - (nav_height * 8.0 + 7.0 * 7.0)
		for child in stack.get_children():
			var button := child as Button
			button.custom_minimum_size = Vector2(108.0 * unit, nav_height)
			button.add_theme_font_size_override("font_size", roundi(11.0 * unit))
	var joystick := hud.joystick
	if joystick != null:
		var joystick_scale := maxf(1.0, unit * 0.65)
		joystick.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
		joystick.scale = Vector2.ONE * joystick_scale
		joystick.pivot_offset = Vector2(0, 170)
		joystick.offset_left = margin
		joystick.offset_right = margin + 170
		joystick.offset_top = -margin - 170
		joystick.offset_bottom = -margin
	# Interaction and avatar switching sit above the joystick, not the navigation or combat buttons.
	for i in range(2):
		var button := hud._touch_interact if i == 0 else hud._touch_switch
		if button == null:
			continue
		button.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
		button.offset_left = margin
		button.offset_right = margin + 106.0 * unit
		var bottom := -margin * 2.0 - 170.0 * maxf(1.0, unit * 0.65) - i * (height + 8.0)
		button.offset_bottom = bottom
		button.offset_top = bottom - height
		button.add_theme_font_size_override("font_size", roundi(13.0 * unit))
	if portrait:
		var minimap := hud._minimap
		if minimap != null:
			var map_size := 94.0 * unit
			minimap.set_layout_rect(100.0 * unit, -margin, map_size)

