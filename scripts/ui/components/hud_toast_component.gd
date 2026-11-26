class_name HUDToastComponent
extends Node
## Owns bounded toast creation, animation and cleanup.

var hud: HUD

func bind(owner: HUD) -> void:
	hud = owner

func show_toast(message: String) -> void:
	if hud == null or hud._toast_box == null:
		return
	while hud._toasts.size() >= 3:
		var oldest: Control = hud._toasts.pop_front()
		if is_instance_valid(oldest):
			oldest.queue_free()
	var panel := UIFactory.panel(Color("#141c30"), Color(UITheme.GOLD.r, UITheme.GOLD.g, UITheme.GOLD.b, 0.55), 10, 1, 10, true)
	panel.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	var text := UIFactory.wrapped(message, 13, UITheme.TEXT)
	text.custom_minimum_size = Vector2(320, 0)
	text.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	panel.add_child(text)
	hud._toast_box.add_child(panel)
	hud._toasts.append(panel)
	panel.modulate = Color(1, 1, 1, 0)
	# Bind the tween to the toast itself so replacing a toast or leaving a map
	# cancels the animation before it can reference a freed Control.
	var tween := panel.create_tween()
	tween.tween_property(panel, "modulate:a", 1.0, 0.18)
	tween.tween_interval(3.0)
	tween.tween_property(panel, "modulate:a", 0.0, 0.35)
	tween.tween_callback(_finish_toast.bind(weakref(panel)))

func _finish_toast(panel_ref: WeakRef) -> void:
	var panel := panel_ref.get_ref() as Control
	if is_instance_valid(panel) and is_instance_valid(hud):
		hud._toasts.erase(panel)
		panel.queue_free()
