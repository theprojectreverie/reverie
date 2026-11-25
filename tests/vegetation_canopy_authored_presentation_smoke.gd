extends Node

const CANOPY_SCENE := preload("res://scenes/world/components/vegetation/vegetation_canopy.tscn")

func _ready() -> void:
	call_deferred("_run")

func _run() -> void:
	var canopy := CANOPY_SCENE.instantiate() as Node2D
	add_child(canopy)
	await get_tree().process_frame
	var player := canopy.get_node_or_null("AnimationPlayer") as AnimationPlayer
	var sprite := canopy.get_node_or_null("Sprite2D") as Sprite2D
	if player == null or sprite == null:
		_fail("Canopy is missing its authored Sprite2D or AnimationPlayer")
		return
	if not player.is_playing() or player.current_animation != "canopy_wind_sway":
		_fail("Canopy wind sway did not autoplay")
		return
	var library := load("res://resources/world/environment/vegetation_canopy_presentation.tres") as AnimationLibrary
	if library == null or not library.has_animation(&"canopy_wind_sway"):
		_fail("Reusable canopy presentation library is missing")
		return
	var animation := library.get_animation(&"canopy_wind_sway")
	if animation.loop_mode != Animation.LOOP_LINEAR or not is_equal_approx(animation.length, 4.0):
		_fail("Canopy wind sway loop or duration is incorrect")
		return
	if animation.get_track_count() != 1 or str(animation.track_get_path(0)) != "Sprite2D:rotation":
		_fail("Canopy wind sway must animate only its authored sprite rotation")
		return
	if sprite.texture == null:
		_fail("Canopy Sprite2D did not initialize its configured texture source")
		return
	print("VEGETATION CANOPY AUTHORED PRESENTATION SMOKE: PASS (autoplay, loop, isolated sway track and configured sprite)")
	canopy.queue_free()
	get_tree().quit(0)

func _fail(message: String) -> void:
	push_error("FAIL: " + message)
	get_tree().quit(1)
