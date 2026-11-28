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
		hud._hint_label.visible = not compact_portrait and not TouchInput.using_touch

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
	var unit := clampf((viewport_size.x if portrait else viewport_size.y) / (390.0 if portrait else 540.0), 0.85, 1.25)
	var margin := 12.0 * unit
	var safe := _safe_insets(viewport_size)
	var left_margin := margin + safe.x
	var right_margin := margin + safe.y
	var bottom_margin := margin + safe.z
	var target_unit := maxf(unit, viewport_size.x / 390.0) if portrait else unit
	var height := 44.0 * target_unit
	var width := 70.0 * target_unit
	var combat := hud._touch_combat
	if combat != null:
		combat.offset_left = -(width * 3.0 + margin * 2.0 + 16.0 + safe.y)
		combat.offset_right = -right_margin
		combat.offset_top = -height - bottom_margin
		combat.offset_bottom = -bottom_margin
		for child in combat.get_children():
			var button := child as Button
			button.custom_minimum_size = Vector2(width, height)
			button.add_theme_font_size_override("font_size", roundi(12.0 * unit))
	var nav_width := maxf(126.0, 126.0 * unit)
	var toggle := hud.get_node_or_null("MobileMenuToggle") as Button
	var nav_bottom := -height - bottom_margin - 8.0
	if toggle != null:
		toggle.offset_left = -right_margin - nav_width
		toggle.offset_right = -right_margin
		toggle.offset_top = nav_bottom - height
		toggle.offset_bottom = nav_bottom
		toggle.custom_minimum_size = Vector2(nav_width, height)
		toggle.add_theme_font_size_override("font_size", roundi(13.0 * unit))
	var stack := hud.get_node_or_null("ActionStack") as GridContainer
	if stack != null:
		# Four rows on compact displays; one column on taller displays.
		stack.columns = 2 if viewport_size.y < 570.0 else 1
		var rows := ceili(8.0 / float(stack.columns))
		var nav_height := maxf(38.0, 40.0 * unit)
		stack.add_theme_constant_override("h_separation", 5)
		stack.add_theme_constant_override("v_separation", 4)
		stack.offset_left = -right_margin - nav_width * stack.columns - 5.0 * (stack.columns - 1)
		stack.offset_right = -right_margin
		stack.offset_bottom = nav_bottom - height - 6.0
		stack.offset_top = stack.offset_bottom - (nav_height * rows + (rows - 1) * 4.0)
		for child in stack.get_children():
			var button := child as Button
			button.custom_minimum_size = Vector2(nav_width, nav_height)
			button.add_theme_font_size_override("font_size", roundi(12.0 * unit))
			button.add_theme_constant_override("icon_max_width", 18)
			# The desktop 12px padding forces 42px+ minimum heights on phones.
			for state in ["normal", "hover", "pressed", "disabled", "focus"]:
				var box := button.get_theme_stylebox(state).duplicate() as StyleBox
				box.content_margin_top = 5.0
				box.content_margin_bottom = 5.0
				box.content_margin_left = 7.0
				box.content_margin_right = 7.0
				button.add_theme_stylebox_override(state, box)
	var joystick := hud.joystick
	if joystick != null:
		var joystick_scale := maxf(1.0, unit * 0.65)
		joystick.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
		joystick.scale = Vector2.ONE * joystick_scale
		joystick.pivot_offset = Vector2(0, 170)
		joystick.offset_left = left_margin
		joystick.offset_right = left_margin + 170
		joystick.offset_top = -bottom_margin - 170
		joystick.offset_bottom = -bottom_margin
	# Interaction and avatar switching sit above the joystick, not the navigation or combat buttons.
	for i in range(2):
		var button := hud._touch_interact if i == 0 else hud._touch_switch
		if button == null:
			continue
		button.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
		button.offset_left = left_margin
		button.offset_right = left_margin + 106.0 * unit
		var bottom := -margin * 2.0 - safe.z - 170.0 * maxf(1.0, unit * 0.65) - i * (height + 8.0)
		button.offset_bottom = bottom
		button.offset_top = bottom - height
		button.add_theme_font_size_override("font_size", roundi(13.0 * unit))
	var minimap := hud._minimap
	if minimap != null:
		var map_size := 116.0 * unit if portrait else 144.0 * unit
		minimap.set_layout_rect(90.0, -right_margin, map_size)
		# Preserve the existing 224px legend and map coordinates, while scaling
		# the complete panel from the top-right instead of clipping its contents.
		minimap.pivot_offset = Vector2(minimap.size.x, 0.0)
		minimap.scale = Vector2.ONE * (0.78 if portrait else 0.85)


func _safe_insets(viewport_size: Vector2) -> Vector3:
	if not OS.has_feature("mobile"):
		return Vector3.ZERO
	var screen := DisplayServer.screen_get_size()
	var area := DisplayServer.get_display_safe_area()
	if screen.x <= 0 or screen.y <= 0 or area.size.x <= 0 or area.size.y <= 0:
		return Vector3.ZERO
	var ratio := viewport_size / Vector2(screen)
	return Vector3(maxf(0.0, area.position.x * ratio.x), maxf(0.0, (screen.x - area.end.x) * ratio.x), maxf(0.0, (screen.y - area.end.y) * ratio.y))