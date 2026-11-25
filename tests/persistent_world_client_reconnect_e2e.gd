extends Node
## Runs the production MultiplayerGateway and actual GameScreen as an authenticated client.
## Environment is supplied only by the local persistent-world E2E runner.

var _started_at := 0.0
var _initial_admission := false
var _saw_disconnect := false
var _saw_reconnecting := false
var _recovered_admission := false
var _failure := ""
var _sync_component: Variant
var _test_local_player: Node2D
var _expected_x := 24.0
var _expected_y := 30.0
var _expected_remote_id := ""
var _expected_remote_x := 40.0
var _expected_remote_y := 60.0

func _ready() -> void:
	call_deferred("_run")

func _run() -> void:
	print("REVERIE_E2E_CLIENT_STAGE: run_started")
	_started_at = Time.get_ticks_msec() / 1000.0
	var api_base := OS.get_environment("REVERIE_E2E_API_BASE")
	var access_token := OS.get_environment("REVERIE_E2E_ACCESS_TOKEN")
	var server_id := OS.get_environment("REVERIE_E2E_SERVER_ID")
	var join_ticket := OS.get_environment("REVERIE_E2E_JOIN_TICKET")
	var endpoint := OS.get_environment("REVERIE_E2E_ENDPOINT")
	var marker_dir := OS.get_environment("REVERIE_E2E_MARKER_DIR")
	var expected_player_id := OS.get_environment("REVERIE_E2E_PLAYER_ID")
	_expected_x = float(OS.get_environment("REVERIE_E2E_EXPECTED_X"))
	_expected_y = float(OS.get_environment("REVERIE_E2E_EXPECTED_Y"))
	_expected_remote_id = OS.get_environment("REVERIE_E2E_EXPECTED_REMOTE_ID")
	_expected_remote_x = float(OS.get_environment("REVERIE_E2E_EXPECTED_REMOTE_X"))
	_expected_remote_y = float(OS.get_environment("REVERIE_E2E_EXPECTED_REMOTE_Y"))
	print("REVERIE_E2E_CLIENT_STAGE: environment_loaded")
	if api_base.is_empty() or access_token.is_empty() or server_id.is_empty() or join_ticket.is_empty() or endpoint.is_empty() or marker_dir.is_empty() or expected_player_id.is_empty():
		_fail("Missing required local E2E environment")
		_write_marker(marker_dir, "failure.json", {"ok":false,"reason":_failure})
		get_tree().quit(1)
		return
	var auth := get_tree().root.get_node_or_null("AuthGateway")
	var gateway := get_tree().root.get_node_or_null("MultiplayerGateway")
	if auth == null or gateway == null:
		_fail("Production auth or multiplayer autoload was not initialized")
		_write_marker(marker_dir, "failure.json", {"ok":false,"reason":_failure})
		get_tree().quit(1)
		return
	# Run the actual authored GameScreen and its world scene, not a stub world.
	# This keeps the real player, collision world, remote avatar root, HUD and
	# production co-op component alive for both clients during reconnect.
	var game_packed := load("res://scenes/game.tscn") as PackedScene
	if game_packed == null:
		_fail("Playable GameScreen scene could not be loaded")
		_write_marker(marker_dir, "failure.json", {"ok":false,"reason":_failure})
		get_tree().quit(1)
		return
	var game := game_packed.instantiate() as GameScreen
	get_tree().root.add_child(game)
	_sync_component = game.coop_sync_component
	_test_local_player = game.world.player if game.world != null else null
	if _sync_component == null or _test_local_player == null:
		_fail("Playable GameScreen did not bind its world sync and local player")
		_write_marker(marker_dir, "failure.json", {"ok":false,"reason":_failure})
		get_tree().quit(1)
		return
	print("REVERIE_E2E_CLIENT_STAGE: playable_game_scene_attached")
	auth.set("api_base_url", api_base)
	auth.set("_access_token", access_token)
	auth.set("_access_token_expires_at", Time.get_unix_time_from_system() + 3600.0)
	gateway.persistent_world_event.connect(_on_world_event.bind(expected_player_id, marker_dir))
	gateway.persistent_world_disconnected.connect(_on_disconnected)
	gateway.persistent_world_reconnecting.connect(_on_reconnecting)
	gateway.persistent_world_connection_failed.connect(_on_connection_failed)
	print("REVERIE_E2E_CLIENT_STAGE: auth_configured")
	var result: Error = gateway.connect_to_persistent_world(server_id, join_ticket, endpoint)
	if result != OK:
		_fail("Production gateway could not start initial connection: " + str(result))
		_write_marker(marker_dir, "failure.json", {"ok":false,"reason":_failure})
		get_tree().quit(1)
		return
	# The GameScreen sync component is already bound to the real world tree.
	print("REVERIE_E2E_CLIENT_STAGE: gateway_connection_started")
	while not _recovered_admission and _failure.is_empty():
		if (Time.get_ticks_msec() / 1000.0) - _started_at > 100.0:
			_fail("Timed out waiting for the production gateway to recover")
			break
		await get_tree().create_timer(0.1).timeout
	if _failure.is_empty() and not _expected_remote_id.is_empty():
		var remote_deadline := Time.get_ticks_msec() + 15000
		var remote_confirmed := false
		while Time.get_ticks_msec() < remote_deadline:
			var remote_players: Dictionary = _sync_component.get("remote_players")
			if remote_players.has(_expected_remote_id):
				var remote_avatar := remote_players[_expected_remote_id] as RemotePlayerAvatar
				if remote_avatar != null and is_equal_approx(remote_avatar.target_position.x, _expected_remote_x) and is_equal_approx(remote_avatar.target_position.y, _expected_remote_y):
					remote_confirmed = true
					_write_marker(marker_dir, "remote-avatar.json", {"ok":true,"remotePlayerId":_expected_remote_id,"x":remote_avatar.target_position.x,"y":remote_avatar.target_position.y})
					break
			await get_tree().create_timer(0.1).timeout
		if not remote_confirmed:
			_fail("Production sync did not restore the other connected Godot client's remote avatar at its authoritative position")
	if _failure.is_empty() and not _verify_remote_snapshot_reconciliation(expected_player_id):
		_fail("Production snapshot duplicate/stale/removal reconciliation checks failed")
	if _failure.is_empty() and not await _exercise_live_movement(marker_dir):
		_fail("Actual player movement did not reach the other production client through authoritative position sync")
	if _failure.is_empty():
		_write_marker(marker_dir, "recovered.json", {"ok":true,"playerId":expected_player_id,"x":_test_local_player.global_position.x,"y":_test_local_player.global_position.y})
		# Keep both production clients connected while the Node harness verifies
		# their live party snapshot from a third observer connection.
		await get_tree().create_timer(25.0).timeout
		gateway.disconnect_from_persistent_world()
		get_tree().quit(0)
	else:
		_write_marker(marker_dir, "failure.json", {"ok":false,"reason":_failure})
		gateway.disconnect_from_persistent_world()
		get_tree().quit(1)

func _on_world_event(event: Dictionary, expected_player_id: String, marker_dir: String) -> void:
	if str(event.get("type", "")) != "world_joined":
		return
	var local_member: Dictionary = {}
	for member in event.get("members", []):
		if member is Dictionary and str(member.get("playerId", member.get("player_id", ""))) == expected_player_id:
			local_member = member
			break
	if local_member.is_empty():
		_fail("world_joined snapshot did not contain the authenticated local player")
		return
	print("REVERIE_E2E_CLIENT_STAGE: snapshot_event ready=", _sync_component.get("_snapshot_ready"), " entities=", _sync_component.get("entities"), " remote=", _sync_component.get("remote_root"), " local=", _sync_component.get("local_player"), " pending=", _sync_component.get("_pending_persistent_world_snapshot"))
	if not _initial_admission:
		_initial_admission = true
		# Verify after the gateway finishes dispatching this world_joined signal.
		call_deferred("_verify_initial_snapshot", marker_dir, expected_player_id)
		return
	if _recovered_admission:
		return
	if not _saw_disconnect or not _saw_reconnecting:
		return
	if not is_equal_approx(float(local_member.get("x", -999999.0)), _expected_x) or not is_equal_approx(float(local_member.get("y", -999999.0)), _expected_y):
		_fail("Recovered snapshot did not restore expected authoritative position: " + str(local_member))
		return
	if not bool(_sync_component.get("_snapshot_ready")) or bool(_test_local_player.get("network_recovery_paused")) or _test_local_player.global_position.distance_to(Vector2(_expected_x, _expected_y)) > 0.1:
		_fail("Production sync component did not unlock movement and apply the recovered local position")
		return
	_recovered_admission = true

func _exercise_live_movement(marker_dir: String) -> bool:
	if _test_local_player == null or not is_instance_valid(_test_local_player):
		_fail("Playable local CharacterBody2D is missing before movement test")
		return false
	if not _test_local_player.has_node("CollisionShape2D"):
		_fail("Playable local player has no authored collision shape")
		return false
	if (_test_local_player.collision_mask & 1) == 0:
		_fail("Playable player collision mask is not checking authored world geometry")
		return false
	if bool(_test_local_player.get("network_recovery_paused")) or not bool(_test_local_player.get("input_enabled")):
		_fail("Playable local player is not enabled for movement after reconnect")
		return false
	var remotes: Dictionary = _sync_component.get("remote_players")
	if not remotes.has(_expected_remote_id):
		_fail("Other client avatar disappeared before movement test")
		return false
	var remote_avatar := remotes[_expected_remote_id] as RemotePlayerAvatar
	var peer_marker_dir := OS.get_environment("REVERIE_E2E_PEER_MARKER_DIR")
	if peer_marker_dir.is_empty():
		_fail("Peer marker directory is missing; synchronized movement start cannot be guaranteed")
		return false
	_write_marker(marker_dir, "movement-ready.json", {"ok":true})
	var peer_deadline := Time.get_ticks_msec() + 20000
	while Time.get_ticks_msec() < peer_deadline and not FileAccess.file_exists(peer_marker_dir.path_join("movement-ready.json")):
		await get_tree().create_timer(0.1).timeout
	if not FileAccess.file_exists(peer_marker_dir.path_join("movement-ready.json")):
		_fail("Other playable client did not reach the synchronized movement start")
		return false
	var start_position := _test_local_player.global_position
	Input.action_press("move_right")
	var move_deadline := Time.get_ticks_msec() + 650
	while Time.get_ticks_msec() < move_deadline:
		await get_tree().physics_frame
	Input.action_release("move_right")
	var settle_deadline := Time.get_ticks_msec() + 1500
	while Time.get_ticks_msec() < settle_deadline and _test_local_player.velocity.length() > 18.0:
		await get_tree().physics_frame
	var moved_position := _test_local_player.global_position
	if moved_position.x < start_position.x + 15.0:
		_fail("Actual CharacterBody2D did not move right under real locomotion input: " + str({"before":start_position,"after":moved_position,"velocity":_test_local_player.get("velocity")}))
		return false
	# Keep pressing into the contacted world obstacle. The collision solver must
	# hold the body at the boundary rather than allowing it to tunnel through.
	var contact_position := moved_position
	Input.action_press("move_right")
	var blocked_deadline := Time.get_ticks_msec() + 400
	while Time.get_ticks_msec() < blocked_deadline:
		await get_tree().physics_frame
	Input.action_release("move_right")
	var blocked_settle_deadline := Time.get_ticks_msec() + 1000
	while Time.get_ticks_msec() < blocked_settle_deadline and _test_local_player.velocity.length() > 18.0:
		await get_tree().physics_frame
	var blocked_position := _test_local_player.global_position
	if blocked_position.distance_to(moved_position) > 2.0:
		_fail("Player crossed or slid through the world obstacle under sustained input: " + str({"contact":moved_position,"afterPush":blocked_position}))
		return false
	moved_position = blocked_position
	var sync_deadline := Time.get_ticks_msec() + 5000
	var remote_moved := false
	while Time.get_ticks_msec() < sync_deadline:
		if not is_instance_valid(remote_avatar):
			break
		if remote_avatar.target_position.distance_to(Vector2(_expected_remote_x, _expected_remote_y)) >= 15.0:
			remote_moved = true
			break
		await get_tree().create_timer(0.1).timeout
	if not is_instance_valid(remote_avatar) or not remote_moved:
		_fail("Other playable client did not receive a live authoritative movement update: " + str({"local":moved_position,"remote":remote_avatar.target_position if is_instance_valid(remote_avatar) else Vector2.INF}))
		return false
	_write_marker(marker_dir, "movement.json", {"ok":true,"before":{"x":start_position.x,"y":start_position.y},"after":{"x":moved_position.x,"y":moved_position.y},"remote":{"x":remote_avatar.target_position.x,"y":remote_avatar.target_position.y},"collisionShape":true,"worldCollisionMask":_test_local_player.collision_mask,"contact":{"x":contact_position.x,"y":contact_position.y},"blockedAfter":{"x":blocked_position.x,"y":blocked_position.y},"slideCollisions":_test_local_player.get_slide_collision_count()})
	return true

func _verify_remote_snapshot_reconciliation(expected_player_id: String) -> bool:
	var fixture_id := "e2e-remote-snapshot-fixture"
	var base_sequence := int(_sync_component.get("_persistent_last_sequence"))
	var snapshot_sequence := base_sequence + 2
	var snapshot := {
		"type":"world_joined",
		"serverId":OS.get_environment("REVERIE_E2E_SERVER_ID"),
		"playerId":expected_player_id,
		"eventSequence":snapshot_sequence,
		"members":[
			{"playerId":expected_player_id,"x":_expected_x,"y":_expected_y},
			{"playerId":_expected_remote_id,"name":"Live Teammate","x":_expected_remote_x,"y":_expected_remote_y},
			{"playerId":fixture_id,"name":"Snapshot Teammate","x":77.0,"y":88.0}
		]
	}
	_sync_component.call("_on_persistent_world_event", snapshot)
	var remotes: Dictionary = _sync_component.get("remote_players")
	if not remotes.has(fixture_id) or not is_equal_approx((remotes[fixture_id] as RemotePlayerAvatar).target_position.x, 77.0) or not is_equal_approx((remotes[fixture_id] as RemotePlayerAvatar).target_position.y, 88.0):
		_fail("Snapshot reconciliation did not create the remote teammate at its authoritative position")
		return false
	_sync_component.call("_on_persistent_world_event", {"type":"position","sequence":snapshot_sequence,"playerId":fixture_id,"x":999.0,"y":999.0})
	if not is_equal_approx((remotes[fixture_id] as RemotePlayerAvatar).target_position.x, 77.0) or not is_equal_approx((remotes[fixture_id] as RemotePlayerAvatar).target_position.y, 88.0):
		_fail("Duplicate position event overwrote the recovered snapshot position")
		return false
	var stale_snapshot := snapshot.duplicate(true)
	stale_snapshot["eventSequence"] = snapshot_sequence - 1
	stale_snapshot["members"] = [
		{"playerId":expected_player_id,"x":_expected_x,"y":_expected_y},
		{"playerId":_expected_remote_id,"name":"Live Teammate","x":_expected_remote_x,"y":_expected_remote_y},
		{"playerId":fixture_id,"name":"Stale Teammate","x":999.0,"y":999.0}
	]
	_sync_component.call("_on_persistent_world_event", stale_snapshot)
	if not is_equal_approx((remotes[fixture_id] as RemotePlayerAvatar).target_position.x, 77.0) or not is_equal_approx((remotes[fixture_id] as RemotePlayerAvatar).target_position.y, 88.0):
		_fail("Stale snapshot overwrote the latest teammate position")
		return false
	var removal_snapshot := snapshot.duplicate(true)
	removal_snapshot["eventSequence"] = snapshot_sequence + 1
	removal_snapshot["members"] = [
		{"playerId":expected_player_id,"x":_expected_x,"y":_expected_y},
		{"playerId":_expected_remote_id,"name":"Live Teammate","x":_expected_remote_x,"y":_expected_remote_y}
	]
	_sync_component.call("_on_persistent_world_event", removal_snapshot)
	if remotes.has(fixture_id):
		_fail("Snapshot reconciliation retained a teammate absent from the authoritative party snapshot")
		return false
	_write_marker(OS.get_environment("REVERIE_E2E_MARKER_DIR"), "snapshot-reconciliation.json", {"ok":true,"remoteCreated":true,"duplicateIgnored":true,"staleSnapshotIgnored":true,"absentRemoteRemoved":true})
	return true

func _verify_initial_snapshot(marker_dir: String, expected_player_id: String) -> void:
	var snapshot_ready := bool(_sync_component.get("_snapshot_ready"))
	var movement_paused := bool(_test_local_player.get("network_recovery_paused"))
	if not snapshot_ready or movement_paused:
		_fail("Production sync component did not apply the initial authoritative snapshot: snapshot_ready=" + str(snapshot_ready) + ", movement_paused=" + str(movement_paused) + ", gateway_connected=" + str(_sync_component.get("_gateway") == get_tree().root.get_node_or_null("MultiplayerGateway")))
		return
	_write_marker(marker_dir, "initial.json", {"ok":true,"playerId":expected_player_id})

func _on_disconnected() -> void:
	if _initial_admission:
		_saw_disconnect = true
		# Let every gateway listener run before checking the sync component.
		call_deferred("_verify_recovery_pause")

func _verify_recovery_pause() -> void:
	if _saw_disconnect and (_test_local_player == null or not bool(_test_local_player.get("network_recovery_paused"))):
		_fail("Production sync component did not pause local movement during the real socket interruption")

func _on_reconnecting(attempt: int, max_attempts: int) -> void:
	_saw_reconnecting = true
	_write_marker(OS.get_environment("REVERIE_E2E_MARKER_DIR"), "reconnecting.json", {"attempt":attempt,"maxAttempts":max_attempts})

func _on_connection_failed(reason: String) -> void:
	if _initial_admission:
		_fail("Production gateway reported terminal reconnect failure: " + reason)

func _fail(reason: String) -> void:
	if _failure.is_empty():
		_failure = reason
		push_error("REVERIE_E2E_CLIENT_FAILURE: " + reason)

func _write_marker(directory: String, filename: String, payload: Dictionary) -> void:
	var file := FileAccess.open(directory.path_join(filename), FileAccess.WRITE)
	if file != null:
		file.store_string(JSON.stringify(payload))
