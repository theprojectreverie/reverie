extends Node

const LIGHT_SCENE := preload("res://scenes/world/components/presentation/localized_light_source.tscn")

func _ready() -> void:
	call_deferred("_run")

func _run() -> void:
	var light := LIGHT_SCENE.instantiate() as Node2D
	add_child(light)
	await get_tree().process_frame
	var player := light.get_node_or_null("AnimationPlayer") as AnimationPlayer
	var point := light.get_node_or_null("PointLight2D") as PointLight2D
	if player == null or point == null:
		_fail("Localized light is missing authored animation or light node")
		return
	if not player.is_playing() or player.current_animation != "village_light_bloom":
		_fail("Village light bloom did not autoplay")
		return
	var library := load("res://resources/world/environment/village_light_presentation.tres") as AnimationLibrary
	if library == null or not library.has_animation(&"village_light_bloom"):
		_fail("Reusable village light animation library is missing")
		return
	var animation := library.get_animation(&"village_light_bloom")
	if animation.loop_mode != Animation.LOOP_LINEAR or not is_equal_approx(animation.length, 3.2):
		_fail("Village light bloom loop or duration is incorrect")
		return
	if animation.get_track_count() != 1 or str(animation.track_get_path(0)) != "PointLight2D:texture_scale":
		_fail("Village light bloom must animate only PointLight2D texture scale")
		return
	light.set_phase_energy(0.4, true)
	if not is_equal_approx(point.energy, 0.36) or not point.enabled:
		_fail("Authored bloom interfered with existing day/night energy control")
		return
	print("VILLAGE LIGHT AUTHORED PRESENTATION SMOKE: PASS (autoplay, loop, isolated track and day/night energy)")
	light.queue_free()
	get_tree().quit(0)

func _fail(message: String) -> void:
	push_error("FAIL: " + message)
	get_tree().quit(1)
