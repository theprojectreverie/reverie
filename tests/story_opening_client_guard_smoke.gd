extends Node
func _ready() -> void:
	call_deferred("_run")
func _run() -> void:
	var policy = preload("res://scripts/online/story_opening_world_sync.gd")
	assert(not policy.village_available({"progress":{"tutorialComplete":false},"servers":[{"region_id":"story_village","endpoint_url":"ws://localhost"}]}))
	assert(not policy.village_available({"progress":{"tutorialComplete":true},"servers":[]}))
	assert(policy.village_available({"progress":{"tutorialComplete":true},"servers":[{"region_id":"story_village","endpoint_url":"ws://localhost"}]}))
	print("PASS village preflight policy")
	if AuthGateway.is_authenticated():
		push_error("Expected isolated unauthenticated test")
		get_tree().quit(1)
		return
	for path in ["res://scenes/world/tutorial_prologue/training_ground_v02.tscn", "res://scenes/world/village/imported_village/village_playable.tscn"]:
		var scene := (load(path) as PackedScene).instantiate()
		add_child(scene)
		await get_tree().create_timer(0.3).timeout
		var sync := scene.get_node_or_null("StoryOpeningWorldSync")
		if sync == null or str(sync.get("_failure")) != "authentication_required" or bool(sync.get("_ready_position")):
			push_error("Opening scene did not fail closed: " + path)
			get_tree().quit(1)
			return
		var player: Player = sync.get("_player")
		if not player.network_recovery_paused or MultiplayerGateway.is_connected_to_persistent_world():
			push_error("Opening scene permitted unauthenticated movement")
			get_tree().quit(1)
			return
		if scene.name == &"StandaloneVillage":
			var fast_travel = preload("res://scripts/world/six_zone_reverie/fast_travel.gd")
			assert(fast_travel.unavailable_reason(scene, "StandaloneZone01") == "Online story fast travel is not available yet")
			assert(not fast_travel.travel(scene, "StandaloneZone01"))
			print("PASS online fast travel guard")
		print("PASS opening client guard: " + path)
		scene.queue_free()
		await get_tree().process_frame
	await AudioDirector.drain_for_shutdown()
	print("STORY_OPENING_CLIENT_GUARD_PASS")
	get_tree().quit(0)
