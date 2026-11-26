extends Node

func _ready() -> void:
	var screen := MapScreen.new()
	screen.size = Vector2(1280, 720)
	add_child(screen)
	await get_tree().process_frame
	if screen._map_canvas == null:
		push_error("[map-ui] Map canvas did not build.")
		screen.queue_free()
		await get_tree().process_frame
		await AudioDirector.drain_for_shutdown()
		get_tree().quit(1)
		return
	screen._map_canvas.queue_redraw()
	print("[map-ui] OK — full map screen and live world-map canvas instantiated.")
	screen.queue_free()
	await get_tree().process_frame
	await AudioDirector.drain_for_shutdown()
	await get_tree().process_frame
	get_tree().quit(0)
