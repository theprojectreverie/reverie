class_name CoopWorldSyncComponent
extends Node
## Bridges the authenticated co-op transport to presentation-only world avatars.
## Server positions are authoritative; local movement is proposed at 10 Hz.

const REMOTE_AVATAR_SCENE: PackedScene = preload("res://scenes/online/remote_player_avatar.tscn")
const SEND_INTERVAL := 0.10
const MAX_BUFFERED_WORLD_EVENTS := 200
const REMOTE_SPAWN_BATCH := 4
const REMOTE_SPAWN_BUDGET_USEC := 2000
var _pending_remote_members: Dictionary = {}
var _remote_sheet_path := ""
var _remote_sheet: SpriteFrames
var _remote_sheet_attempted := false
var _remote_sheet_loading := false
var _remote_sheet_generation := 0

var game: Node
var active_world: Node2D
var entities: Node2D
var remote_root: Node2D
var remote_players: Dictionary = {}
var local_player: Node2D
var local_player_id := ""
var active_region_id := ""
var last_sequence := 0
var _send_elapsed := 0.0
var _resume_requested := false
var _snapshot_ready := false
var _pending_snapshot_events: Array[Dictionary] = []
var _snapshot_event_overflow := false
var _out_of_order_events: Dictionary = {}
var _replay_request_pending := false
var _active_lobby_id := ""
var patrol_cleared: Dictionary = {}
var exploration_cleared: Array[String] = []
const SHARED_OBJECTIVES := {"six_zone_willow_fields": ["willow_bridge", "willow_ruins"], "six_zone_elderwood_grove": ["elderwood_memorial", "elderwood_pillar"], "six_zone_forsaken_ruins": ["ruins_western_brazier", "ruins_central_brazier", "ruins_eastern_brazier", "cassien_resurrection"]}
var _gateway: Node
var _pending_persistent_world_snapshot: Dictionary = {}
var _recovery_status: Label
var _world_recovering := false
var _persistent_last_sequence := 0
var _persistent_interest_windows := false
var _persistent_world_server_id := ""

func _ready() -> void:
	_create_recovery_indicator()
	_gateway = get_node_or_null("/root/MultiplayerGateway")
	if _gateway == null:
		return
	_gateway.server_event.connect(_on_server_event)
	_gateway.lobby_connected.connect(_on_lobby_connected)
	_gateway.lobby_disconnected.connect(_on_lobby_disconnected)
	_gateway.connection_failed.connect(_on_lobby_connection_failed)
	_gateway.persistent_world_event.connect(_on_persistent_world_event)
	_gateway.persistent_world_disconnected.connect(_on_persistent_world_disconnected)
	_gateway.persistent_world_reconnecting.connect(_on_persistent_world_reconnecting)
	_gateway.persistent_world_recovered.connect(_on_persistent_world_recovered)
	_gateway.persistent_world_connection_failed.connect(_on_persistent_world_connection_failed)

func _exit_tree() -> void:
	_set_local_network_recovery_paused(false)
	if _gateway != null:
		if _gateway.server_event.is_connected(_on_server_event):
			_gateway.server_event.disconnect(_on_server_event)
		if _gateway.lobby_connected.is_connected(_on_lobby_connected):
			_gateway.lobby_connected.disconnect(_on_lobby_connected)
		if _gateway.lobby_disconnected.is_connected(_on_lobby_disconnected):
			_gateway.lobby_disconnected.disconnect(_on_lobby_disconnected)
		if _gateway.connection_failed.is_connected(_on_lobby_connection_failed):
			_gateway.connection_failed.disconnect(_on_lobby_connection_failed)
		if _gateway.persistent_world_event.is_connected(_on_persistent_world_event):
			_gateway.persistent_world_event.disconnect(_on_persistent_world_event)
		if _gateway.persistent_world_disconnected.is_connected(_on_persistent_world_disconnected):
			_gateway.persistent_world_disconnected.disconnect(_on_persistent_world_disconnected)
		if _gateway.persistent_world_reconnecting.is_connected(_on_persistent_world_reconnecting):
			_gateway.persistent_world_reconnecting.disconnect(_on_persistent_world_reconnecting)
		if _gateway.persistent_world_recovered.is_connected(_on_persistent_world_recovered):
			_gateway.persistent_world_recovered.disconnect(_on_persistent_world_recovered)
		if _gateway.persistent_world_connection_failed.is_connected(_on_persistent_world_connection_failed):
			_gateway.persistent_world_connection_failed.disconnect(_on_persistent_world_connection_failed)
	_clear_remote_players()

func _create_recovery_indicator() -> void:
	var layer := CanvasLayer.new()
	layer.name = "CoopRecoveryLayer"
	layer.layer = 30
	add_child(layer)
	_recovery_status = Label.new()
	_recovery_status.name = "RecoveryStatus"
	_recovery_status.visible = false
	_recovery_status.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_recovery_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_recovery_status.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_recovery_status.add_theme_font_size_override("font_size", 13)
	_recovery_status.add_theme_color_override("font_color", Color("#f1e7d2"))
	_recovery_status.add_theme_color_override("font_shadow_color", Color("#211a2b"))
	_recovery_status.add_theme_constant_override("shadow_offset_x", 1)
	_recovery_status.add_theme_constant_override("shadow_offset_y", 1)
	# Recovery messaging uses the same authored ornamental frame language
	# as battle HUD panels instead of a generic flat code-drawn plate.
	var plate_texture := load("res://assets/ui/battle/panels/battle_status_panel.png") as Texture2D
	if plate_texture != null:
		var plate := StyleBoxTexture.new()
		plate.texture = plate_texture
		plate.texture_margin_left = 28.0
		plate.texture_margin_right = 28.0
		plate.texture_margin_top = 20.0
		plate.texture_margin_bottom = 20.0
		plate.content_margin_left = 14.0
		plate.content_margin_right = 14.0
		plate.content_margin_top = 7.0
		plate.content_margin_bottom = 7.0
		_recovery_status.add_theme_stylebox_override("normal", plate)
	_recovery_status.anchor_left = 0.5
	_recovery_status.anchor_right = 0.5
	_recovery_status.anchor_top = 0.0
	_recovery_status.anchor_bottom = 0.0
	_recovery_status.offset_left = -190.0
	_recovery_status.offset_right = 190.0
	_recovery_status.offset_top = 18.0
	_recovery_status.offset_bottom = 52.0
	layer.add_child(_recovery_status)

func _set_recovery_status(message: String) -> void:
	if _recovery_status == null:
		return
	_recovery_status.text = message
	_recovery_status.visible = not message.is_empty()

func _set_local_network_recovery_paused(paused: bool) -> void:
	if local_player != null and is_instance_valid(local_player) and local_player.has_method("set_network_recovery_paused"):
		local_player.call("set_network_recovery_paused", paused)

func bind(owner_game: Node) -> void:
	game = owner_game
	active_region_id = str(game.get("current_region_id"))
	var session: Node = game.get("world_session") as Node
	if session != null and not session.world_changed.is_connected(_on_world_changed):
		session.world_changed.connect(_on_world_changed)
	_attach_world(game.get("world") as Node2D)

func bind_standalone(world: Node2D, player: Node2D, region_id: String) -> void:
	active_world = world
	entities = world
	local_player = player
	active_region_id = region_id
	_ensure_remote_root()

func _ensure_remote_root() -> void:
	if entities == null or is_instance_valid(remote_root):
		return
	remote_root = Node2D.new()
	remote_root.name = "RemotePlayers"
	entities.add_child(remote_root)
	remote_root.top_level = true
	remote_root.global_position = Vector2.ZERO

func _process(delta: float) -> void:
	if _snapshot_ready and not _world_recovering:
		_drain_remote_admissions()
	if _gateway == null or not _snapshot_ready or local_player == null or not is_instance_valid(local_player):
		return
	if not _gateway.is_connected_to_lobby() and not _gateway.is_connected_to_persistent_world():
		return
	_send_elapsed += delta
	if _send_elapsed < SEND_INTERVAL:
		return
	_send_elapsed = 0.0
	if _gateway.is_connected_to_persistent_world():
		_gateway.send_world_position(local_player.global_position)
	else:
		_gateway.send_position(local_player.global_position, active_region_id)

func _on_world_changed(next_world: Node2D, region_id: String) -> void:
	active_region_id = region_id
	_attach_world(next_world)

func _attach_world(next_world: Node2D) -> void:
	_clear_remote_players()
	active_world = next_world
	local_player = null
	entities = null
	_snapshot_ready = false
	_pending_snapshot_events.clear()
	_snapshot_event_overflow = false
	if active_world == null:
		return
	var entity_value: Variant = active_world.get("entities")
	entities = entity_value as Node2D
	if entities == null:
		return
	local_player = active_world.get("player") as Node2D
	_set_local_network_recovery_paused(_world_recovering)
	remote_root = Node2D.new()
	remote_root.name = "RemotePlayers"
	remote_root.top_level = true
	remote_root.global_position = Vector2.ZERO
	entities.add_child(remote_root)
	if not _pending_persistent_world_snapshot.is_empty():
		_apply_persistent_world_snapshot(_pending_persistent_world_snapshot)
		_pending_persistent_world_snapshot.clear()
	if _gateway != null and _gateway.is_connected_to_lobby():
		_resume_requested = false
		_gateway.resume_from_sequence(last_sequence)

func _on_lobby_connected(lobby_id: String) -> void:
	if lobby_id != _active_lobby_id:
		_active_lobby_id = lobby_id
		_clear_remote_players()
		local_player_id = ""
		last_sequence = 0
		_out_of_order_events.clear()
		_snapshot_event_overflow = false
		_replay_request_pending = false
	_resume_requested = true
	_snapshot_ready = false
	_pending_snapshot_events.clear()
	if _world_recovering:
		_set_recovery_status("Connection restored — synchronizing your party…")
	if _gateway != null:
		_gateway.resume_from_sequence(last_sequence)

func _on_persistent_world_event(event: Dictionary) -> void:
	var event_type := str(event.get("type", ""))
	if event_type=="player_titles":
		_apply_title_refresh(event)
		return
	if event_type == "world_joined":
		var incoming_server_id := str(event.get("serverId", ""))
		var incoming_player_id := str(event.get("playerId", ""))
		var snapshot_sequence := int(event.get("eventSequence", 0))
		# A recovery snapshot is authoritative only when it identifies its world,
		# local member, and sequence cursor. Never let an incomplete/stale packet
		# reset the cursor or roll rendered party state backwards.
		var valid_empty_cursor := bool(event.get("interestWindows", false)) and event.has("eventSequence") and snapshot_sequence == 0
		if incoming_server_id.is_empty() or incoming_player_id.is_empty() or (snapshot_sequence <= 0 and not valid_empty_cursor):
			_snapshot_ready = false
			_set_local_network_recovery_paused(true)
			_world_recovering = true
			_set_recovery_status("World snapshot is incomplete. Movement remains paused while synchronization retries.")
			push_warning("Persistent-world snapshot was missing its server, player, or event sequence; it was ignored.")
			return
		if incoming_server_id != _persistent_world_server_id:
			_persistent_world_server_id = incoming_server_id
			_persistent_last_sequence = 0
		if snapshot_sequence < _persistent_last_sequence:
			return
		local_player_id = incoming_player_id
		_persistent_interest_windows = bool(event.get("interestWindows", false))
		_persistent_last_sequence = maxi(_persistent_last_sequence, snapshot_sequence)
		if entities == null or remote_root == null:
			_pending_persistent_world_snapshot = event.duplicate(true)
			_snapshot_ready = false
			return
		_apply_persistent_world_snapshot(event)
		return
	if event_type == "world_position_window":
		if not _persistent_interest_windows:
			return
		var first := int(event.get("fromSequence", 0))
		var last := int(event.get("sequence", 0))
		var members: Variant = event.get("members")
		if last <= _persistent_last_sequence or first <= 0 or first > last or first > _persistent_last_sequence + 1 or not members is Array:
			return
		_persistent_last_sequence = last
		if not _pending_persistent_world_snapshot.is_empty():
			var local_members: Array = []
			for member in _pending_persistent_world_snapshot.get("members", []):
				if member is Dictionary and str(member.get("playerId","")) == local_player_id:
					local_members.append(member)
			_pending_persistent_world_snapshot["members"] = local_members + members
			_pending_persistent_world_snapshot["eventSequence"] = last
		elif _snapshot_ready and remote_root != null:
			_apply_interest_members(members)
		return
	var sequence := int(event.get("sequence", 0))
	if sequence > 0:
		if sequence <= _persistent_last_sequence:
			return
		if sequence > _persistent_last_sequence + 1:
			# MultiplayerGateway requests a replay and withholds events beyond a gap.
			return
		_persistent_last_sequence = sequence
	if event_type == "player_joined":
		var joined_id := str(event.get("playerId", ""))
		if not _persistent_interest_windows and not joined_id.is_empty() and joined_id != local_player_id:
			_ensure_remote(joined_id, str(event.get("name", "Wanderer")), Vector2.ZERO, event.get("title",null))
	elif event_type == "player_left":
		_remove_remote(str(event.get("playerId", "")))
	elif event_type == "position":
		_apply_position(str(event.get("playerId", "")), Vector2(float(event.get("x", 0.0)), float(event.get("y", 0.0))), 0)

# Large negotiated snapshots may create many expensive avatar scenes.
# Keep at most one pending presentation record per player; newest windows
# replace stale coordinates and cancel departed players before allocation.
# Request only when an expedition peer is actually needed. The independent
# loader consumes its own request even if this map disappears mid-load.
func _request_remote_sheet() -> void:
	if _remote_sheet_attempted or not active_region_id.begins_with("six_zone_"):
		return
	_remote_sheet_attempted = true
	_remote_sheet_path = MainCharacterRoster.world_sheet_path("kael")
	if _remote_sheet_path.is_empty():
		return
	var loader := Node.new()
	loader.set_script(load("res://scripts/online/remote_sheet_prefetch.gd"))
	loader.name = "RemoteSheetPrefetch"
	_remote_sheet_loading = true
	loader.completed.connect(_on_remote_sheet_loaded.bind(_remote_sheet_generation))
	get_tree().root.add_child(loader)
	loader.begin(_remote_sheet_path)

func _on_remote_sheet_loaded(sheet: SpriteFrames, generation: int) -> void:
	if generation != _remote_sheet_generation:
		return
	_remote_sheet_loading = false
	_remote_sheet = sheet

func _stage_remote_member(id: String, label: String, position: Vector2, title: Variant, defer_spawn: bool) -> void:
	if not remote_players.has(id):
		_request_remote_sheet()
	if not remote_players.has(id) and (defer_spawn or _remote_sheet_loading or _pending_remote_members.has(id)):
		_pending_remote_members[id] = {"name":label,"position":position,"title":title}
		return
	var avatar := _ensure_remote(id,label,position,title)
	if avatar != null:
		avatar.set_authoritative_position(position)

func _drain_remote_admissions() -> void:
	if not is_instance_valid(remote_root) or _pending_remote_members.is_empty() or _remote_sheet_loading:
		return
	var started := Time.get_ticks_usec()
	var count := 0
	for id in _pending_remote_members.keys():
		var member: Dictionary = _pending_remote_members[id]
		_pending_remote_members.erase(id)
		var avatar := _ensure_remote(str(id), str(member["name"]), member["position"], member["title"])
		if avatar != null:
			avatar.set_authoritative_position(member["position"])
		count += 1
		if count >= REMOTE_SPAWN_BATCH or Time.get_ticks_usec()-started >= REMOTE_SPAWN_BUDGET_USEC:
			break

func _apply_interest_members(members: Array) -> void:
	var present: Dictionary = {}
	var defer_spawn := members.size() > REMOTE_SPAWN_BATCH or not _pending_remote_members.is_empty()
	for member in members:
		if not member is Dictionary:
			continue
		var player_id := str(member.get("playerId", ""))
		if player_id.is_empty() or player_id == local_player_id:
			continue
		var position := Vector2(float(member.get("x", 0.0)), float(member.get("y", 0.0)))
		if not position.is_finite():
			continue
		present[player_id] = true
		_stage_remote_member(player_id, str(member.get("name","Wanderer")), position, member.get("title",null), defer_spawn)
	for id in _pending_remote_members.keys():
		if not present.has(id):
			_pending_remote_members.erase(id)
	for player_id in remote_players.keys():
		if not present.has(player_id):
			_remove_remote(str(player_id))

func _apply_persistent_world_snapshot(event: Dictionary) -> void:
	local_player_id = str(event.get("playerId", local_player_id))
	_snapshot_ready = false
	_pending_remote_members.clear()
	var present_ids: Dictionary = {}
	var local_member_found := false
	var members: Array = event.get("members", [])
	var defer_spawn := _persistent_interest_windows and members.size() > REMOTE_SPAWN_BATCH+1
	for member in members:
		if not member is Dictionary:
			continue
		var member_id := str(member.get("playerId", member.get("player_id", member.get("id", ""))))
		if member_id.is_empty():
			continue
		var has_position := member.get("x") != null and member.get("y") != null
		var member_position := Vector2(float(member.get("x", 0.0)), float(member.get("y", 0.0)))
		if member_id == local_player_id:
			local_member_found = true
			if local_player != null and is_instance_valid(local_player) and has_position:
				local_player.global_position = member_position
			continue
		present_ids[member_id] = true
		if _persistent_interest_windows and not remote_players.has(member_id):
			_stage_remote_member(member_id, str(member.get("name","Wanderer")), member_position, member.get("title",null), defer_spawn)
		else:
			var avatar := _ensure_remote(member_id, str(member.get("name", "Wanderer")), member_position, member.get("title",null))
			if avatar != null and has_position:
				avatar.set_authoritative_position(member_position)
	for existing_id in remote_players.keys():
		if not present_ids.has(existing_id):
			_remove_remote(str(existing_id))
	_persistent_last_sequence = maxi(_persistent_last_sequence, int(event.get("eventSequence", event.get("sequence", 0))))
	_snapshot_ready = local_member_found
	_set_local_network_recovery_paused(not local_member_found)
	_world_recovering = not local_member_found
	if local_member_found:
		_set_recovery_status("")
	else:
		_set_recovery_status("World snapshot could not verify your player. Movement is paused — return to the world browser to rejoin.")
		push_warning("Persistent-world snapshot did not contain the local player; movement remains paused.")

func _on_persistent_world_disconnected() -> void:
	# connect_to_persistent_world() resets an unused peer before the first
	# admission and emits this signal as part of setup. It is not a lost session.
	if local_player_id.is_empty() and _persistent_world_server_id.is_empty():
		return
	# Preserve the last rendered party state while the transport retries.
	_pending_remote_members.clear()
	_snapshot_ready = false
	_set_local_network_recovery_paused(true)
	_pending_persistent_world_snapshot.clear()
	if _gateway == null or not _gateway.has_method("is_persistent_world_reconnect_enabled") or _gateway.is_persistent_world_reconnect_enabled():
		_world_recovering = true
		_set_recovery_status("Connection interrupted — restoring your world…")
	else:
		_set_local_network_recovery_paused(false)
		local_player_id = ""
		_persistent_last_sequence = 0
		_persistent_world_server_id = ""
		_world_recovering = false
		_set_recovery_status("")
		_clear_remote_players()

func _on_persistent_world_reconnecting(attempt: int, max_attempts: int) -> void:
	_world_recovering = true
	_set_recovery_status("Reconnecting to your world  ·  %d/%d" % [attempt, max_attempts])

func _on_persistent_world_recovered(_server_id: String) -> void:
	_world_recovering = true
	_set_recovery_status("Connection restored — synchronizing your world…")

func _on_persistent_world_connection_failed(reason: String) -> void:
	_pending_remote_members.clear()
	_world_recovering = false
	_snapshot_ready = false
	_set_local_network_recovery_paused(true)
	var message := reason.strip_edges()
	if message.is_empty():
		message = "The shared-world connection could not be restored."
	_set_recovery_status(message + " Movement is paused. Return to the world browser to rejoin.")

func _on_lobby_disconnected() -> void:
	_resume_requested = false
	_snapshot_ready = false
	_pending_snapshot_events.clear()
	_snapshot_event_overflow = false
	_out_of_order_events.clear()
	_replay_request_pending = false
	if _gateway != null and _gateway.has_method("is_lobby_reconnect_enabled") and _gateway.is_lobby_reconnect_enabled():
		_world_recovering = true
		_set_local_network_recovery_paused(true)
		_set_recovery_status("Connection interrupted — restoring your party…")
		return
	local_player_id = ""
	_world_recovering = false
	_set_recovery_status("")
	_clear_remote_players()

func _on_lobby_connection_failed(reason: String) -> void:
	_world_recovering = false
	_snapshot_ready = false
	_set_local_network_recovery_paused(true)
	var message := reason.strip_edges()
	if message.is_empty():
		message = "Party connection lost."
	_set_recovery_status(message + " Movement is paused. Return to the co-op lobby to reconnect.")

func _on_server_event(event: Dictionary) -> void:
	var event_type := str(event.get("type", ""))
	if event_type=="player_titles":
		_apply_title_refresh(event)
		return
	if event_type == "monster_motion":
		if _snapshot_ready and active_region_id == str(event.get("regionId", "")):
			for state in event.get("monsters", []):
				if state is Dictionary:
					_apply_coop_monster_motion(state)
		return
	if event_type == "connected":
		local_player_id = str(event.get("playerId", ""))
		if not _resume_requested:
			_resume_requested = true
			_gateway.resume_from_sequence(last_sequence)
		return
	if event_type == "snapshot":
		if int(event.get("sequence", 0)) < last_sequence:
			return
		_snapshot_ready = _apply_snapshot(event)
		if _snapshot_ready and active_region_id.begins_with("six_zone_"):
			AuthGateway.refresh_online_wallet()
		_world_recovering = not _snapshot_ready
		_set_local_network_recovery_paused(not _snapshot_ready)
		if _snapshot_ready:
			_set_recovery_status("")
			_flush_snapshot_events()
			if _snapshot_event_overflow:
				_snapshot_event_overflow = false
				_request_missing_events()
		else:
			_set_recovery_status("Party snapshot could not verify your player. Movement is paused — return to the co-op lobby to rejoin.")
		return
	if not _snapshot_ready and event_type in ["replay", "position", "player_joined", "player_left", "emote", "interaction"]:
		if _pending_snapshot_events.size() >= MAX_BUFFERED_WORLD_EVENTS:
			_pending_snapshot_events.clear()
			_snapshot_event_overflow = true
		else:
			_pending_snapshot_events.append(event.duplicate(true))
		return
	_apply_live_event(event)

func _apply_live_event(event: Dictionary) -> void:
	var event_type := str(event.get("type", ""))
	if event_type == "replay":
		for item in event.get("events", []):
			if item is Dictionary:
				_queue_replay_event(item)
		return
	var sequence := int(event.get("sequence", 0))
	if sequence <= 0:
		_apply_live_event_now(event)
		return
	if sequence <= last_sequence:
		return
	if sequence > last_sequence + 1:
		_out_of_order_events[sequence] = {"replay":false,"event":event.duplicate(true)}
		if _out_of_order_events.size() > MAX_BUFFERED_WORLD_EVENTS:
			_out_of_order_events.clear()
			_replay_request_pending = false
		_request_missing_events()
		return
	_apply_live_event_now(event)
	_drain_ordered_events()

func _apply_live_event_now(event: Dictionary) -> void:
	var event_type := str(event.get("type", ""))
	var event_sequence := int(event.get("sequence", 0))
	if event_type == "position":
		_apply_position(str(event.get("playerId", "")), Vector2(float(event.get("x", 0.0)), float(event.get("y", 0.0))), event_sequence)
	elif event_type == "player_joined":
		var joined_id := str(event.get("playerId", ""))
		if not joined_id.is_empty() and joined_id != local_player_id:
			_ensure_remote(joined_id, str(event.get("name","Wanderer")), Vector2.ZERO, event.get("title",null))
		_advance_sequence(event_sequence)
	elif event_type == "player_left":
		_remove_remote(str(event.get("playerId", "")))
		_advance_sequence(event_sequence)
	elif event_type == "interaction":
		_apply_monster_state(event, true)
		_play_remote_monster_attack(event)
		_apply_coop_counterattack(event, true)
		for reward in event.get("rewards", []):
			if reward is Dictionary and str(reward.get("playerId", "")) == local_player_id:
				AuthGateway.refresh_online_wallet()
				var message := "Expedition reward: +%d online gold, +%d online XP" % [int(reward.get("gold",0)),int(reward.get("xp",0))]
				for item_id in reward.get("items", {}):
					message += ", +%d %s" % [int(reward["items"][item_id]), str(ContentDB.get_item(item_id).get("name",item_id))]
				EventBus.toast_requested.emit(message)
		_advance_sequence(event_sequence)
	elif event_type == "emote":
		_advance_sequence(event_sequence)

func _queue_replay_event(item: Dictionary) -> void:
	var sequence := int(item.get("sequence", 0))
	if sequence <= 0 or sequence <= last_sequence:
		return
	if sequence > last_sequence + 1:
		_out_of_order_events[sequence] = {"replay":true,"event":item.duplicate(true)}
		if _out_of_order_events.size() > MAX_BUFFERED_WORLD_EVENTS:
			_out_of_order_events.clear()
			_replay_request_pending = false
		_request_missing_events()
		return
	_apply_replay_event_now(item)
	_drain_ordered_events()

func _request_missing_events() -> void:
	if _replay_request_pending or _gateway == null or not _gateway.is_connected_to_lobby():
		return
	_replay_request_pending = true
	_gateway.resume_from_sequence(last_sequence)

func _drain_ordered_events() -> void:
	while _out_of_order_events.has(last_sequence + 1):
		var next: Dictionary = _out_of_order_events[last_sequence + 1]
		_out_of_order_events.erase(last_sequence + 1)
		if bool(next.get("replay", false)):
			_apply_replay_event_now(next.get("event", {}))
		else:
			_apply_live_event_now(next.get("event", {}))
	if _out_of_order_events.is_empty():
		_replay_request_pending = false

func _flush_snapshot_events() -> void:
	var pending := _pending_snapshot_events.duplicate()
	_pending_snapshot_events.clear()
	for event in pending:
		if str(event.get("type", "")) == "replay":
			for item in event.get("events", []):
				if item is Dictionary and int(item.get("sequence", 0)) > last_sequence:
					_apply_replay_event(item)
		elif int(event.get("sequence", 0)) > last_sequence:
			_apply_live_event(event)

func _apply_snapshot(event: Dictionary) -> bool:
	if active_region_id.begins_with("six_zone_"):
		for member in event.get("members", []):
			if member is Dictionary and str(member.get("region_id", "")) != active_region_id:
				return false
	_ensure_remote_root()
	if entities == null or remote_root == null:
		return false
	var local_member_found := local_player_id.is_empty() and not active_region_id.begins_with("six_zone_")
	for member in event.get("members", []):
		if member is Dictionary and str(member.get("id", "")) == local_player_id:
			local_member_found = true
			break
	if not local_member_found:
		return false
	var present_ids: Dictionary = {}
	for member in event.get("members", []):
		if not member is Dictionary:
			continue
		var id := str(member.get("id", ""))
		if id.is_empty():
			continue
		var spawn_position := Vector2.ZERO
		if member.get("x") != null and member.get("y") != null:
			spawn_position = Vector2(float(member.get("x")), float(member.get("y")))
		if id == local_player_id:
			if local_player != null and is_instance_valid(local_player):
				local_player.global_position = spawn_position
			continue
		present_ids[id] = true
		var avatar := _ensure_remote(id, str(member.get("name", "Wanderer")), spawn_position, member.get("title",null))
		if avatar != null and member.get("x") != null and member.get("y") != null:
			avatar.set_authoritative_position(spawn_position)
	for existing_id in remote_players.keys():
		if not present_ids.has(existing_id):
			var stale: Node = remote_players[existing_id]
			if is_instance_valid(stale):
				stale.queue_free()
			remote_players.erase(existing_id)
	if SHARED_OBJECTIVES.has(active_region_id):
		_apply_exploration_progress(event.get("explorationCleared", []))
	if active_region_id == "six_zone_royal_gate":
		patrol_cleared.clear()
		for id in event.get("patrolCleared", []):
			if str(id) in ["royal_gate_patrol_1", "royal_gate_patrol_2"]:
				patrol_cleared[str(id)] = true
		_update_patrol_hud()
	for monster in event.get("monsters", []):
		if monster is Dictionary:
			_apply_monster_state(monster)
	var health: Dictionary = event.get("combatHealth", {})
	if is_instance_valid(local_player) and active_region_id in ["six_zone_royal_gardens", "six_zone_royal_gate", "six_zone_willow_fields", "six_zone_forsaken_ruins", "six_zone_ruined_tower"]:
		local_player.get_node("WorldCombatComponent").apply_coop_health(float(health.get(local_player_id,100)))
	var snapshot_sequence := int(event.get("sequence", last_sequence))
	if snapshot_sequence > last_sequence:
		last_sequence = snapshot_sequence
	for buffered_sequence in _out_of_order_events.keys():
		if int(buffered_sequence) <= last_sequence:
			_out_of_order_events.erase(buffered_sequence)
	_replay_request_pending = false
	_drain_ordered_events()
	if _gateway != null and last_sequence > 0:
		_gateway.acknowledge_sequence(last_sequence)
	return true

func _apply_replay_event(item: Dictionary) -> void:
	_queue_replay_event(item)

func _apply_replay_event_now(item: Dictionary) -> void:
	var sequence := int(item.get("sequence", 0))
	var actor_id := str(item.get("actor_player_id", item.get("playerId", "")))
	var event_type := str(item.get("event_type", item.get("type", "")))
	var payload: Dictionary = item.get("payload", {}) if item.get("payload", {}) is Dictionary else {}
	if event_type == "position":
		_apply_position(actor_id, Vector2(float(payload.get("x", item.get("x", 0.0))), float(payload.get("y", item.get("y", 0.0)))), sequence)
	elif event_type == "player_joined":
		if not actor_id.is_empty() and actor_id != local_player_id:
			_ensure_remote(actor_id, str(payload.get("name","Wanderer")), Vector2.ZERO, payload.get("title",null))
		_advance_sequence(sequence)
	elif event_type == "player_left":
		_remove_remote(actor_id)
		_advance_sequence(sequence)
	elif event_type == "interaction":
		payload["playerId"] = actor_id
		_apply_monster_state(payload)
		_apply_coop_counterattack(payload, false)
		if not payload.get("rewards", []).is_empty():
			AuthGateway.refresh_online_wallet()
		_advance_sequence(sequence)
	else:
		_advance_sequence(sequence)

func _play_remote_monster_attack(event: Dictionary) -> void:
	if str(event.get("kind", "")) != "monster_hit":
		return
	var attacker := str(event.get("playerId", ""))
	if attacker == local_player_id or not remote_players.has(attacker):
		return
	var avatar = remote_players[attacker]
	if not is_instance_valid(avatar):
		return
	for target in get_tree().get_nodes_in_group("world_action_targets"):
		if str(target.get("group_id")) == str(event.get("monsterId", "")):
			avatar.play_confirmed_attack(target.global_position)
			return
func _apply_coop_counterattack(event: Dictionary, animate: bool) -> void:
	if active_region_id not in ["six_zone_royal_gardens", "six_zone_royal_gate", "six_zone_willow_fields", "six_zone_forsaken_ruins", "six_zone_ruined_tower"] or not event.get("counterattack") is Dictionary:
		return
	var counter: Dictionary = event["counterattack"]
	var victim := str(counter.get("playerId", ""))
	var target_position := Vector2.ZERO
	if victim == local_player_id and is_instance_valid(local_player):
		local_player.get_node("WorldCombatComponent").apply_coop_health(float(counter.get("hp",100)),bool(counter.get("knockedOut",false)),animate)
		target_position = local_player.global_position
	elif remote_players.has(victim) and is_instance_valid(remote_players[victim]):
		var avatar = remote_players[victim]
		target_position = avatar.global_position
		if animate:
			avatar.visual.play(ActorVisual.S_DEFEAT if bool(counter.get("knockedOut",false)) else ActorVisual.S_DAMAGE)
	else:
		return
	if animate:
		for monster in get_tree().get_nodes_in_group("world_action_targets"):
			if str(monster.get("group_id")) == str(event.get("monsterId", "")) and monster.has_method("play_coop_counterattack"):
				monster.play_coop_counterattack(target_position)
				return
func _apply_coop_monster_motion(state: Dictionary) -> void:
	for target in get_tree().get_nodes_in_group("world_action_targets"):
		if is_instance_valid(target) and target.has_method("apply_coop_motion") and str(target.get("group_id")) == str(state.get("monsterId", "")):
			target.apply_coop_motion(Vector2(float(state.get("x",0)),float(state.get("y",0))),str(state.get("mode","patrol")),str(state.get("targetId", "")) if state.get("targetId") != null else "")
			return
func _update_patrol_hud() -> void:
	if not is_instance_valid(active_world):
		return
	var hud := active_world.get_node_or_null("UI/HUD") as HUD
	if hud != null:
		hud.set_world_info("Royal Gate", "Patrol cleared (2/2)" if patrol_cleared.size() == 2 else "Shared patrol %d/2" % patrol_cleared.size())

func next_exploration_objective() -> String:
	if active_region_id == "six_zone_forsaken_ruins":
		var cassien = active_world.get_node_or_null("CassienRitual") if is_instance_valid(active_world) else null
		if cassien == null or not cassien.coop_defeated:
			return ""
	for id in SHARED_OBJECTIVES.get(active_region_id, []):
		if str(id) not in exploration_cleared:
			return str(id)
	return ""

func _apply_exploration_progress(completed: Array) -> void:
	var previous := exploration_cleared.size()
	exploration_cleared.clear()
	for id in SHARED_OBJECTIVES.get(active_region_id, []):
		if id in completed:
			exploration_cleared.append(str(id))
	if not is_instance_valid(active_world):
		return
	var hud := active_world.get_node_or_null("UI/HUD") as HUD
	if hud != null and SHARED_OBJECTIVES.has(active_region_id):
		if active_region_id == "six_zone_forsaken_ruins":
			var next := next_exploration_objective()
			var message := "Challenge Cassien" if next.is_empty() and exploration_cleared.size() < 4 else "Purify braziers %d/3" % mini(3, exploration_cleared.size())
			if next == "cassien_resurrection": message = "Return to Cassien at the tomb"
			if exploration_cleared.size() == 4: message = "Ravienna resurrected"
			hud.set_world_info("Forsaken Ruins", message)
		else:
			var title := "Willow Fields" if active_region_id == "six_zone_willow_fields" else "Elderwood Grove"
			hud.set_world_info(title, "Shared exploration %d/2" % exploration_cleared.size() if exploration_cleared.size() < 2 else "Exploration complete (2/2)")
	for objective in get_tree().get_nodes_in_group("quest_exploration_targets"):
		if active_world.is_ancestor_of(objective) and objective.has_method("refresh_shared_objective"):
			objective.refresh_shared_objective()
	if exploration_cleared.size() > previous and _snapshot_ready:
		EventBus.toast_requested.emit("Party exploration: %d/%d" % [exploration_cleared.size(), SHARED_OBJECTIVES[active_region_id].size()])

func _apply_monster_state(event: Dictionary, live: bool = false) -> void:
	if active_region_id == "six_zone_forsaken_ruins" and str(event.get("kind", "")) == "boss_guard" and str(event.get("monsterId", "")) == "cassien_encounter":
		var cassien = active_world.get_node_or_null("CassienRitual")
		if cassien != null:
			cassien.apply_coop_guard_confirmation(event)
		return
	if active_region_id == "six_zone_forsaken_ruins" and str(event.get("monsterId", "")) == "cassien_encounter":
		var cassien = active_world.get_node_or_null("CassienRitual")
		if cassien != null:
			cassien.apply_coop_boss_state(event, live)
			_apply_exploration_progress(exploration_cleared.duplicate())
		return
	if str(event.get("kind", "")) == "exploration_objective":
		if str(event.get("regionId", "")) == active_region_id and event.get("completed") is Array:
			_apply_exploration_progress(event.completed)
		return
	if active_region_id == "six_zone_royal_gate" and str(event.get("kind", "")) == "monster_hit" and float(event.get("hp", 100)) <= 0.0:
		var id := str(event.get("monsterId", ""))
		if id in ["royal_gate_patrol_1", "royal_gate_patrol_2"]:
			patrol_cleared[id] = true
			_update_patrol_hud()
	if active_region_id == "six_zone_ruined_tower" and str(event.get("kind", "")) == "boss_guard" and str(event.get("monsterId", "")) == "revienna_encounter":
		var boss = active_world.get_node_or_null("ReviennaEncounter")
		if boss != null:
			boss.apply_coop_guard_confirmation(event)
		return
	if active_region_id == "six_zone_ruined_tower" and str(event.get("monsterId", "")) == "revienna_encounter":
		var boss = active_world.get_node_or_null("ReviennaEncounter")
		if boss != null:
			boss.apply_coop_boss_state(event, live)
		return
	if active_region_id not in ["six_zone_royal_gardens", "six_zone_royal_gate", "six_zone_willow_fields"] or str(event.get("kind", "")) != "monster_hit":
		return
	for target in get_tree().get_nodes_in_group("world_action_targets"):
		if is_instance_valid(target) and target.has_method("apply_coop_monster_state") and str(target.get("group_id")) == str(event.get("monsterId", "")):
			target.apply_coop_monster_state(float(event.get("hp",100)),float(event.get("deadUntil",0)))
			return

func _apply_position(player_id: String, next_position: Vector2, sequence: int) -> void:
	if sequence > 0 and sequence <= last_sequence:
		return
	if player_id.is_empty() or player_id == local_player_id:
		_advance_sequence(sequence)
		return
	if _pending_remote_members.has(player_id):
		_pending_remote_members[player_id]["position"] = next_position
		_advance_sequence(sequence)
		return
	var avatar := _ensure_remote(player_id, "Wanderer", next_position)
	if avatar != null:
		avatar.set_authoritative_position(next_position)
	_advance_sequence(sequence)

# Cosmetic-only data never participates in movement sequencing or creates avatars.
func _apply_title_refresh(event:Dictionary) -> void:
	if not _snapshot_ready:return
	for entry in event.get("players",[]):
		if not entry is Dictionary:continue
		var id:=str(entry.get("playerId",""))
		if _pending_remote_members.has(id):
			_pending_remote_members[id]["title"] = str(entry.get("title",""))
		if not remote_players.has(id):continue
		var avatar=remote_players[id]
		if is_instance_valid(avatar):
			avatar.set_display_title(str(entry.get("title","")))

func _ensure_remote(player_id: String, label: String, initial_position: Vector2, title:Variant=null) -> RemotePlayerAvatar:
	if remote_players.has(player_id) and is_instance_valid(remote_players[player_id]):
		var existing := remote_players[player_id] as RemotePlayerAvatar
		if not label.is_empty() and label != "Wanderer" and existing.display_name != label:
			existing.display_name = label
			if is_instance_valid(existing.name_label):
				existing.name_label.text = label
		if title!=null and existing.display_title!=str(title):existing.set_display_title(str(title))
		return existing
	if remote_root == null:
		return null
	var avatar := REMOTE_AVATAR_SCENE.instantiate() as RemotePlayerAvatar
	avatar.name = "Remote_" + player_id.replace("-", "").substr(0, 12)
	avatar.expedition_kael = active_region_id.begins_with("six_zone_")
	avatar.configure(player_id, label, initial_position)
	if title!=null:avatar.set_display_title(str(title))
	remote_root.add_child(avatar)
	if active_region_id.begins_with("six_zone_") and is_instance_valid(local_player):
		avatar.scale = local_player.scale
	remote_players[player_id] = avatar
	return avatar

func _remove_remote(player_id: String) -> void:
	_pending_remote_members.erase(player_id)
	if player_id.is_empty() or not remote_players.has(player_id):
		return
	var avatar: Node = remote_players[player_id]
	if is_instance_valid(avatar):
		avatar.queue_free()
	remote_players.erase(player_id)

func _advance_sequence(sequence: int) -> void:
	if sequence <= 0 or sequence <= last_sequence:
		return
	last_sequence = sequence
	if _gateway != null:
		_gateway.acknowledge_sequence(last_sequence)

func _clear_remote_players() -> void:
	_remote_sheet_generation += 1
	_remote_sheet_loading = false
	_remote_sheet_attempted = false
	_remote_sheet_path = ""
	_remote_sheet = null
	_pending_remote_members.clear()
	remote_players.clear()
	if is_instance_valid(remote_root):
		remote_root.queue_free()
	remote_root = null
