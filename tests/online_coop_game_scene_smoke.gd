extends Node

var failures := 0

func _ready() -> void:
	call_deferred("_run")

func _check(condition: bool, label: String) -> void:
	if condition:
		print("PASS ", label)
	else:
		failures += 1
		push_error("FAIL " + label)

func _run() -> void:
	var packed := load("res://scenes/game.tscn") as PackedScene
	_check(packed != null, "Playable GameScreen scene loads")
	if packed == null:
		get_tree().quit(1)
		return
	var game := packed.instantiate() as GameScreen
	add_child(game)
	for _frame in range(3):
		await get_tree().process_frame
	var sync := game.coop_sync_component
	_check(sync != null and sync.game == game, "GameScreen binds its authored co-op sync component")
	if sync == null:
		game.queue_free()
		get_tree().quit(1)
		return
	_check(sync.active_world == game.world and sync.local_player == game.world.player, "Co-op sync attaches to the live playable world and local player")
	_check(sync.entities == game.world.entities and sync.remote_root != null and sync.remote_root.get_parent() == game.world.entities, "Remote party avatars are layered into the actual world entity tree")
	var saved_position: Vector2 = game.world.player.global_position
	var gateway: Node = get_node("/root/MultiplayerGateway")
	var old_reconnect_enabled := bool(gateway.get("_world_reconnect_enabled"))
	var old_server_id := str(gateway.get("_world_server_id"))
	gateway.set("_world_reconnect_enabled", true)
	gateway.set("_world_server_id", "game-scene-recovery-test")
	sync._on_persistent_world_event({"type":"world_joined","serverId":"game-scene-recovery-test","eventSequence":1,"playerId":"game-local-player","members":[{"playerId":"game-local-player","name":"Local","x":60.0,"y":70.0},{"playerId":"game-party-member","name":"Party Member","x":120.0,"y":140.0},{"playerId":"game-party-member-2","name":"Second Member","x":180.0,"y":200.0}]})
	_check(sync._snapshot_ready and game.world.player.global_position.distance_to(Vector2(60.0, 70.0)) < 0.1, "Actual GameScreen player applies the authoritative admission snapshot")
	_check(sync.remote_players.has("game-party-member") and sync.remote_players.has("game-party-member-2"), "Actual GameScreen displays both remote party avatars")
	var remote_root := sync.remote_root
	_check(remote_root.get_child_count() == 2, "Two party members create exactly two world avatar nodes")
	sync._on_persistent_world_event({"type":"world_joined","serverId":"game-scene-recovery-test","eventSequence":1,"playerId":"game-local-player","members":[{"playerId":"game-local-player","name":"Local","x":60.0,"y":70.0},{"playerId":"game-party-member","name":"Party Member","x":120.0,"y":140.0},{"playerId":"game-party-member-2","name":"Second Member","x":180.0,"y":200.0}]})
	_check(remote_root.get_child_count() == 2, "Repeated identical snapshot does not duplicate remote avatars")
	await get_tree().process_frame
	var first_remote := sync.remote_players.get("game-party-member") as RemotePlayerAvatar
	_check(first_remote != null and first_remote.visual != null and first_remote.name_label != null and first_remote.name_label.text == "Party Member", "Remote avatar builds its character artwork and player name label")
	_check(first_remote != null and first_remote.get_class() == "Node2D" and first_remote.get_node_or_null("CollisionShape2D") == null, "Remote presentation avatars do not introduce phantom physics blockers")
	if first_remote != null:
		var prior_position := first_remote.position
		first_remote.set_authoritative_position(Vector2(220.0, 240.0))
		first_remote._process(0.05)
		_check(first_remote.target_position == Vector2(220.0, 240.0) and first_remote.visual.walking, "Remote movement updates its interpolation target and walk animation")
		_check(first_remote.position.distance_to(prior_position) > 0.1 and first_remote.position.distance_to(Vector2(220.0, 240.0)) > 0.1, "Remote avatar interpolates smoothly toward the server position")
	gateway.set("_world_reconnect_enabled", true)
	gateway.set("_world_server_id", "game-scene-recovery-test")
	sync._on_persistent_world_disconnected()
	_check(game.world.player.network_recovery_paused and sync._recovery_status.visible, "Actual playable player locks movement and displays recovery feedback on disconnect")
	_check(FileAccess.get_file_as_string("res://scripts/characters/components/player_locomotion_component.gd").contains("not bool(body.get(\"network_recovery_paused\"))"), "Actual player locomotion gates input while network recovery is active")
	sync._on_persistent_world_event({"type":"world_joined","serverId":"game-scene-recovery-test","eventSequence":2,"playerId":"game-local-player","members":[{"playerId":"game-local-player","name":"Local","x":80.0,"y":90.0},{"playerId":"game-party-member","name":"Party Member","x":150.0,"y":160.0}]})
	_check(sync._snapshot_ready and not game.world.player.network_recovery_paused, "Actual playable player unlocks only after authoritative snapshot resynchronization")
	_check(game.world.player.global_position.distance_to(Vector2(80.0, 90.0)) < 0.1, "Actual GameScreen restores authoritative local position after reconnect")
	var remote := sync.remote_players.get("game-party-member") as RemotePlayerAvatar
	_check(remote != null and remote.target_position == Vector2(150.0, 160.0), "Actual GameScreen restores remote party position after reconnect")
	_check(not sync.remote_players.has("game-party-member-2"), "Reconnect snapshot removes absent party members from the live roster")
	await get_tree().process_frame
	_check(remote_root.get_child_count() == 1, "Removed party avatars leave no stale world nodes after frame cleanup")
	game.world.player.global_position = saved_position
	game.world.player.network_recovery_paused = false
	gateway.set("_world_reconnect_enabled", old_reconnect_enabled)
	gateway.set("_world_server_id", old_server_id)
	game.free()
	await get_tree().process_frame
	# This isolated headless scene starts the global AudioDirector and may trigger
	# hover/music streams during HUD construction. Drain playback explicitly so
	# the process exits without orphan AudioStreamPlayback resources.
	var audio_director := get_node_or_null("/root/AudioDirector")
	if audio_director != null and audio_director.has_method("stop_all_audio_immediately"):
		audio_director.call("stop_all_audio_immediately")
		await get_tree().create_timer(0.35).timeout
	print("CO-OP GAME SCENE SMOKE: ", 19 - failures, " passed, ", failures, " failed")
	get_tree().quit(0 if failures == 0 else 1)
