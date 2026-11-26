extends CanvasLayer
const TRAVEL = preload("res://scripts/world/six_zone_reverie/fast_travel.gd")
const CHECKPOINT = preload("res://scripts/world/six_zone_reverie/six_zone_checkpoint.gd")
var _destination_packed: PackedScene
var _load_finished := false

func begin(zone: Node2D, destination: String) -> void:
	if not TRAVEL.unavailable_reason(zone, destination).is_empty():
		queue_free()
		return
	var tree := get_tree()
	zone.set_meta("fast_travel_visual_pending", true)
	var player := zone.get("checkpoint_player") as CharacterBody2D
	if is_instance_valid(player):
		player.input_enabled = false
		player.velocity = Vector2.ZERO
	TouchInput.release()
	$Cover/Destination.text = "Travelling to " + str(TRAVEL.NAMES[destination])
	$AnimationPlayer.play("depart")
	var loader := $ResourceLoader as LoadingResourceComponent
	loader.scene_loaded.connect(func(packed: PackedScene) -> void:
		_destination_packed = packed
		_load_finished = true
	)
	loader.load_failed.connect(func() -> void: _load_finished = true)
	# Start only the confirmed destination. Never retain a speculative map cache.
	loader.begin(str(CHECKPOINT.SCENES[destination]))
	await $AnimationPlayer.animation_finished
	while not _load_finished:
		await tree.process_frame
	if not is_instance_valid(zone) or tree.current_scene != zone:
		queue_free()
		return
	zone.set_meta("fast_travel_visual_pending", false)
	if _destination_packed == null or not TRAVEL.travel(zone, destination, _destination_packed):
		$Cover/Destination.text = "Travel unavailable"
		$AnimationPlayer.play("arrive")
		await $AnimationPlayer.animation_finished
		if is_instance_valid(zone):
			var router := zone.get_node_or_null("OverlayRouter")
			if is_instance_valid(player) and (router == null or router.active_overlay == null):
				player.input_enabled = true
		queue_free()
		return
	_destination_packed = null
	await tree.scene_changed
	var arrival := tree.current_scene
	if arrival != null:
		arrival.set_meta("fast_travel_visual_pending", true)
		player = arrival.get("checkpoint_player") as CharacterBody2D
		if is_instance_valid(player):
			player.input_enabled = false
			player.velocity = Vector2.ZERO
	$Cover/Destination.text = str(TRAVEL.NAMES[destination])
	$AnimationPlayer.play("arrive")
	await $AnimationPlayer.animation_finished
	if is_instance_valid(arrival):
		arrival.set_meta("fast_travel_visual_pending", false)
		if is_instance_valid(player):
			player.input_enabled = true
	queue_free()

func _input(_event: InputEvent) -> void:
	get_viewport().set_input_as_handled()
