extends SceneTree

class RecoveryPlayerStub:
	extends Node2D
	var network_recovery_paused := false
	func set_network_recovery_paused(paused: bool) -> void:
		network_recovery_paused = paused

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var packed := load("res://scenes/online/remote_player_avatar.tscn") as PackedScene
	assert(packed != null, "Remote avatar scene must load")
	var sync := CoopWorldSyncComponent.new()
	root.add_child(sync)
	await process_frame
	var initial_remote_root := Node2D.new()
	root.add_child(initial_remote_root)
	sync.remote_root = initial_remote_root
	sync._on_persistent_world_disconnected()
	assert(sync.remote_root == initial_remote_root, "Initial transport reset must not destroy the prepared remote-avatar layer before first admission")
	sync.remote_root = null
	initial_remote_root.queue_free()
	assert(sync._recovery_status != null and not sync._recovery_status.visible, "Recovery status stays hidden during normal play")
	var recovery_style := sync._recovery_status.get_theme_stylebox("normal") as StyleBoxTexture
	assert(recovery_style != null and recovery_style.texture != null and recovery_style.texture.resource_path.ends_with("battle_status_panel.png"), "Recovery status must use the authored battle-panel artwork")
	sync._on_persistent_world_reconnecting(2, 5)
	assert(sync._recovery_status.visible and sync._recovery_status.text.contains("2/5"), "Reconnect attempts are communicated with a compact in-game status")
	sync._on_persistent_world_recovered("server-alpha")
	assert(sync._recovery_status.visible and sync._recovery_status.text.contains("synchronizing"), "Transport recovery remains visible until snapshot reconciliation completes")
	sync._set_recovery_status("")
	assert(not sync._recovery_status.visible, "Recovery status clears after synchronization")
	sync.last_sequence = 19
	sync._snapshot_event_overflow = true
	sync._on_lobby_connected("lobby-alpha")
	assert(sync.last_sequence == 0, "A new lobby must not reuse the previous lobby's event cursor")
	assert(not sync._snapshot_event_overflow, "A new lobby must clear the previous lobby's snapshot overflow state")
	sync.last_sequence = 7
	sync._on_lobby_connected("lobby-alpha")
	assert(sync.last_sequence == 7, "Reconnecting to the same lobby must preserve its replay cursor")
	sync._on_lobby_disconnected()
	sync.last_sequence = 0
	var layer := Node2D.new()
	layer.name = "RemotePlayersTest"
	root.add_child(layer)
	sync.remote_root = layer
	sync.entities = layer
	var avatar := sync._ensure_remote("player-remote-1", "Friend", Vector2(120.0, 240.0))
	assert(avatar != null, "Remote avatar should instantiate")
	assert(sync.remote_players.has("player-remote-1"), "Remote avatar should be tracked by player ID")
	assert(avatar.player_id == "player-remote-1", "Remote avatar should retain player ID")
	avatar.set_authoritative_position(Vector2(180.0, 300.0))
	assert(avatar.target_position == Vector2(180.0, 300.0), "Authoritative position should update interpolation target")
	sync._remove_remote("player-remote-1")
	assert(not sync.remote_players.has("player-remote-1"), "Player-left should remove remote avatar mapping")
	sync.local_player_id = "local-player"
	sync.last_sequence = 3
	sync._snapshot_ready = true
	sync._on_server_event({"type":"player_joined","playerId":"friend-2","sequence":4})
	assert(sync.remote_players.has("friend-2"), "Live player_joined event should create a remote avatar")
	sync._on_server_event({"type":"player_left","playerId":"friend-2","sequence":5})
	assert(not sync.remote_players.has("friend-2"), "Live player_left event should remove a remote avatar")
	sync._snapshot_ready = false
	sync._on_server_event({"type":"player_joined","playerId":"friend-4","sequence":306})
	assert(sync.remote_players.has("friend-4") == false, "Live membership events should wait until the initial snapshot is reconciled")
	sync._on_server_event({"type":"snapshot","members":[{"id":"local-player","name":"Local","x":"40.0","y":"50.0"},{"id":"friend-3","name":"Friend","x":"310.0","y":"420.0"}],"sequence":305,"requires_resync":true})
	assert(sync.last_sequence == 306, "Snapshot recovery should resume cleanly from the snapshot sequence and apply newer buffered events")
	assert(sync.remote_players.has("friend-3"), "Resync snapshot should recreate party members")
	assert(sync.remote_players.has("friend-4"), "Events newer than the snapshot should be replayed after membership reconciliation")
	assert((sync.remote_players["friend-3"] as RemotePlayerAvatar).target_position == Vector2(310.0, 420.0), "Resync snapshot should restore last known member positions")
	# A future event must wait for the missing sequence instead of advancing the cursor.
	sync.last_sequence = 10
	sync._snapshot_ready = true
	sync._on_server_event({"type":"position","playerId":"friend-3","x":120.0,"y":120.0,"sequence":12})
	assert(sync.last_sequence == 10, "Out-of-order live event must not advance the cursor across a gap")
	assert(sync._out_of_order_events.has(12), "Future live event should be buffered by sequence")
	sync._on_server_event({"type":"position","playerId":"friend-3","x":110.0,"y":110.0,"sequence":11})
	assert(sync.last_sequence == 12, "Receiving the missing event should drain buffered contiguous events")
	assert((sync.remote_players["friend-3"] as RemotePlayerAvatar).target_position == Vector2(120.0, 120.0), "Buffered event should apply after the missing sequence")
	assert(sync._out_of_order_events.is_empty(), "Ordered event buffer should empty after contiguous drain")
	# A prolonged gap must not allow unbounded client memory growth.
	sync.last_sequence = 1000
	for sequence in range(1002, 1204):
		sync._on_server_event({"type":"emote","playerId":"friend-3","emoteId":"wave","sequence":sequence})
	assert(sync._out_of_order_events.size() <= sync.MAX_BUFFERED_WORLD_EVENTS, "Out-of-order event buffer must remain bounded")
	# Events received before the first snapshot must also stay bounded.
	sync._snapshot_ready = false
	for sequence in range(1, 202):
		sync._on_server_event({"type":"emote","sequence":sequence})
	assert(sync._pending_snapshot_events.size() <= sync.MAX_BUFFERED_WORLD_EVENTS, "Pre-snapshot event queue must remain bounded")
	assert(sync._snapshot_event_overflow, "Pre-snapshot overflow must be remembered for replay recovery")
	sync._on_lobby_disconnected()
	assert(not sync._snapshot_event_overflow, "Disconnect must clear the snapshot overflow flag")
	# Persistent regional sessions use ticket admission and a membership snapshot, not lobby replay cursors.
	var persistent_layer := Node2D.new()
	persistent_layer.name = "PersistentRemotePlayersTest"
	root.add_child(persistent_layer)
	sync.remote_root = persistent_layer
	sync.entities = persistent_layer
	var persistent_local_player := RecoveryPlayerStub.new()
	root.add_child(persistent_local_player)
	sync.local_player = persistent_local_player
	sync._on_persistent_world_event({"type":"world_joined","serverId":"server-a","eventSequence":10,"playerId":"local-player","members":[{"playerId":"local-player","name":"Local","x":44.0,"y":55.0},{"playerId":"friend-persistent","name":"Friend","x":110.0,"y":220.0}]})
	assert(sync._snapshot_ready, "Persistent world admission should unlock world synchronization only after the local member is present")
	assert(not persistent_local_player.network_recovery_paused, "An authoritative initial snapshot should leave player locomotion enabled")
	assert(sync.local_player_id == "local-player", "Persistent world snapshot should identify the local player")
	assert(persistent_local_player.global_position == Vector2(44.0, 55.0), "Persistent world snapshot should restore the local player's authoritative position")
	assert(sync.remote_players.has("friend-persistent"), "Persistent world snapshot should create remote party avatars")
	assert((sync.remote_players["friend-persistent"] as RemotePlayerAvatar).target_position == Vector2(110.0, 220.0), "Persistent world snapshot should restore remote positions from camel-case playerId members")
	sync._on_persistent_world_event({"type":"position","playerId":"friend-persistent","x":222.0,"y":333.0,"sequence":11})
	assert((sync.remote_players["friend-persistent"] as RemotePlayerAvatar).target_position == Vector2(222.0, 333.0), "Persistent world positions should update remote interpolation")
	assert(sync._persistent_last_sequence == 11, "Persistent-world event cursor should advance only after applying the next ordered event")
	sync._on_persistent_world_event({"type":"position","playerId":"friend-persistent","x":999.0,"y":999.0,"sequence":11})
	assert((sync.remote_players["friend-persistent"] as RemotePlayerAvatar).target_position == Vector2(222.0, 333.0), "Duplicate persistent-world events must not overwrite newer state")
	sync._on_persistent_world_event({"type":"position","playerId":"friend-persistent","x":888.0,"y":888.0,"sequence":13})
	assert(sync._persistent_last_sequence == 11, "Persistent-world sequence gaps must not advance the local cursor")
	sync._on_persistent_world_event({"type":"position","playerId":"friend-persistent","x":333.0,"y":444.0,"sequence":12})
	assert(sync._persistent_last_sequence == 12 and (sync.remote_players["friend-persistent"] as RemotePlayerAvatar).target_position == Vector2(333.0, 444.0), "The missing ordered event should apply after the gap is filled")
	sync._on_persistent_world_event({"type":"player_left","playerId":"friend-persistent","sequence":13})
	assert(not sync.remote_players.has("friend-persistent"), "Persistent world departures should remove remote avatars")
	sync._on_persistent_world_event({"type":"player_joined","playerId":"friend-persistent"})
	sync._on_persistent_world_event({"type":"position","playerId":"friend-persistent","x":250.0,"y":260.0})
	var transport: Node = root.get_node("MultiplayerGateway")
	transport.set("_world_server_id", "test-server")
	transport.set("_world_reconnect_enabled", true)
	sync._on_persistent_world_disconnected()
	assert(not sync._snapshot_ready, "Persistent world disconnect must pause local movement until a fresh snapshot arrives")
	assert(persistent_local_player.network_recovery_paused, "A disconnected co-op player must have local locomotion locked during recovery")
	var locomotion_source := FileAccess.get_file_as_string("res://scripts/characters/components/player_locomotion_component.gd")
	assert(locomotion_source.contains('not bool(body.get("network_recovery_paused"))'), "Player locomotion must respect the co-op recovery movement lock")
	assert(sync.remote_root == persistent_layer and sync.remote_players.has("friend-persistent"), "Reconnect grace should preserve the existing avatar layer while the snapshot is pending")
	sync._on_persistent_world_event({"type":"world_joined","serverId":"server-a","eventSequence":20,"playerId":"local-player","members":[{"playerId":"local-player","name":"Local","x":60.0,"y":70.0},{"playerId":"friend-persistent","name":"Friend","x":330.0,"y":440.0}]})
	assert(sync._snapshot_ready, "A reconnect snapshot should re-enable movement after authoritative membership is restored")
	assert(not persistent_local_player.network_recovery_paused, "Authoritative recovery snapshot should release the locomotion lock")
	assert(persistent_local_player.global_position == Vector2(60.0, 70.0), "Reconnect snapshot should correct local position drift")
	assert((sync.remote_players["friend-persistent"] as RemotePlayerAvatar).target_position == Vector2(330.0, 440.0), "Reconnect snapshot should replace stale remote positions")
	# A delayed older snapshot must not roll the world back after a newer reconciliation.
	sync._on_persistent_world_event({"type":"world_joined","serverId":"server-a","eventSequence":19,"playerId":"local-player","members":[{"playerId":"local-player","name":"Local","x":1.0,"y":1.0}]})
	assert(sync._snapshot_ready and persistent_local_player.global_position == Vector2(60.0, 70.0), "Older snapshots must not overwrite a newer recovered world")
	# An incomplete snapshot must neither roll back state nor release the recovery lock.
	sync._on_persistent_world_event({"type":"world_joined","serverId":"server-a","eventSequence":0,"playerId":"local-player","members":[{"playerId":"local-player","name":"Stale Local","x":2.0,"y":3.0}]})
	assert(sync._persistent_last_sequence == 20 and persistent_local_player.global_position == Vector2(60.0, 70.0), "A zero-sequence snapshot must not reset the cursor or overwrite authoritative positions")
	assert(not sync._snapshot_ready and persistent_local_player.network_recovery_paused, "An incomplete recovery snapshot must keep locomotion paused")
	# A subsequent valid snapshot can complete recovery normally.
	sync._on_persistent_world_event({"type":"world_joined","serverId":"server-a","eventSequence":20,"playerId":"local-player","members":[{"playerId":"local-player","name":"Local","x":60.0,"y":70.0},{"playerId":"friend-persistent","name":"Friend","x":330.0,"y":440.0}]})
	assert(sync._snapshot_ready and not persistent_local_player.network_recovery_paused, "A valid authoritative snapshot should release the recovery lock")
	# A malformed current snapshot must never silently unlock the local player.
	sync._on_persistent_world_event({"type":"world_joined","serverId":"server-a","eventSequence":20,"playerId":"local-player","members":[{"playerId":"friend-persistent","name":"Friend","x":330.0,"y":440.0}]})
	assert(not sync._snapshot_ready and persistent_local_player.network_recovery_paused, "Snapshot without local membership must keep locomotion locked")
	assert(sync._recovery_status.visible and sync._recovery_status.text.contains("could not verify your player"), "Missing local membership must show an actionable recovery warning")
	sync._on_persistent_world_connection_failed("Your sign-in session expired. Sign in again.")
	assert(persistent_local_player.network_recovery_paused, "Terminal reconnect failure must not resume movement")
	assert(sync._recovery_status.visible and sync._recovery_status.text.contains("sign-in session expired"), "Terminal reconnect reason should be shown to the player")
	# The lobby WebSocket recovery path must apply the same movement lock.
	transport.set("_reconnect_enabled", true)
	transport.set("_lobby_id", "lobby-recovery-test")
	sync._on_lobby_disconnected()
	assert(persistent_local_player.network_recovery_paused, "Lobby disconnect must also pause local locomotion during automatic reconnect")
	assert(sync._recovery_status.visible and sync._recovery_status.text.contains("restoring your party"), "Lobby recovery should explain that the party session is being restored")
	sync._on_lobby_connection_failed("Reconnect attempts exhausted")
	assert(persistent_local_player.network_recovery_paused and sync._recovery_status.text.contains("Reconnect attempts exhausted"), "Terminal lobby recovery failure must keep movement paused and explain why")
	sync.queue_free()
	layer.queue_free()
	persistent_local_player.queue_free()
	await process_frame

	print("[online_coop_world_sync_smoke] PASS")
	quit()
