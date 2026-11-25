extends Node

func _ready() -> void:
	call_deferred("_run")

func _run() -> void:
	var packed := load("res://scenes/environment/forest/forest_environment.tscn") as PackedScene
	assert(packed != null, "Forest environment scene must load")
	var forest := packed.instantiate() as Node2D
	assert(forest != null, "Forest environment instance must be created")
	add_child(forest)
	await get_tree().process_frame
	var wind := forest.get_node("WindController") as ForestWindController
	var wind_player := forest.get_node("WindAnimationPlayer") as AnimationPlayer
	assert(wind != null and wind.wind_material != null, "Shared wind material must initialize")
	assert(wind_player != null and wind_player.has_animation(&"breeze") and wind_player.has_animation(&"gust"), "Wind timeline clips must be authored")
	assert(wind_player.current_animation == "breeze" and wind_player.is_playing(), "Forest must start its authored breeze timeline")
	wind_player.play(&"gust")
	wind_player.advance(0.8)
	assert(wind.wind_intensity > 1.4, "Authored gust timeline must raise wind intensity")
	var drift := forest.get_node("Ambient/CanopyDrift") as Node2D
	assert(drift != null, "Reusable canopy drift scene must be instanced")
	var drift_player := drift.get_node("AnimationPlayer") as AnimationPlayer
	assert(drift_player != null and drift_player.has_animation(&"canopy_drift"), "Canopy drift must have an authored animation")
	assert(drift_player.is_playing(), "Canopy drift timeline must autoplay")
	var leaf_a := drift.get_node("LeafA") as Polygon2D
	var start_position := leaf_a.position
	drift_player.advance(1.5)
	assert(not leaf_a.position.is_equal_approx(start_position), "Leaf nodes must move on the authored timeline")
	assert(drift.get_node("LeafB") is Polygon2D and drift.get_node("LeafC") is Polygon2D, "Three authored leaf nodes must exist")
	var firefly_scene := load("res://scenes/environment/forest/forest_firefly.tscn") as PackedScene
	assert(firefly_scene != null, "Reusable firefly scene must load")
	var firefly := firefly_scene.instantiate() as Node2D
	add_child(firefly)
	await get_tree().process_frame
	var firefly_art := firefly.get_node("Sprite") as Node2D
	var firefly_player := firefly.get_node("AnimationPlayer") as AnimationPlayer
	assert(firefly_art != null and firefly_art.get_node_or_null("Glow") is Polygon2D and firefly_art.get_node_or_null("Body") is Polygon2D, "Firefly silhouette must be editor-authored polygon geometry")
	assert(firefly_player != null and firefly_player.is_playing(), "Firefly hover must use its authored timeline")
	var firefly_start := firefly_art.position
	firefly_player.advance(1.1)
	assert(not firefly_art.position.is_equal_approx(firefly_start), "Firefly hover motion must advance on its authored timeline")
	firefly.call("set_activity", 0.0)
	assert(not firefly.visible and not firefly_player.is_playing(), "Daylight activity must hide and pause fireflies")
	firefly.call("set_activity", 1.0)
	assert(firefly.visible and firefly_player.is_playing(), "Night activity must restore and resume fireflies")
	var greenward_scene := load("res://scenes/world/greenward_world.tscn") as PackedScene
	assert(greenward_scene != null, "Playable Greenward world scene must load with ambient drift integration")
	var greenward := greenward_scene.instantiate() as Node2D
	assert(greenward.get_node_or_null("EnvironmentPresentation/AmbientDrift") != null, "Playable Greenward world must instance the reusable ambient drift scene")
	var config := load("res://resources/world/environment/greenward_presentation.tres") as Resource
	var config_component := load("res://scripts/world/components/world_presentation_config_component.gd").new() as Node
	var greenward_drift := greenward.get_node("EnvironmentPresentation/AmbientDrift") as Node2D
	config_component.configure(config, null, null, null, null, null, null, greenward_drift)
	assert(greenward_drift.visible, "Playable Greenward ambient drift must follow the enabled presentation setting")
	config.set("ambient_particles_enabled", false)
	config_component.configure(config, null, null, null, null, null, null, greenward_drift)
	assert(not greenward_drift.visible, "Playable Greenward ambient drift must respect the ambient presentation toggle")
	config_component.free()
	greenward.free()
	firefly.free()
	print("FOREST ENVIRONMENT PRESENTATION SMOKE: PASS (wind, canopy, authored firefly, Greenward integration and config gating)")
	get_tree().quit(0)
