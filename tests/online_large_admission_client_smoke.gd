extends SceneTree

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var gateway: Node = root.get_node("MultiplayerGateway")
	gateway.set_process(false)
	var listener := TCPServer.new()
	assert(listener.listen(19089, "127.0.0.1") == OK)
	var client := WebSocketPeer.new()
	assert(client.connect_to_url("ws://127.0.0.1:19089") == OK)
	var sender := WebSocketPeer.new()
	var accepted := false
	for frame in range(240):
		client.poll()
		if not accepted and listener.is_connection_available():
			assert(sender.accept_stream(listener.take_connection()) == OK)
			accepted = true
		if accepted:
			sender.poll()
		if accepted and sender.get_ready_state() == WebSocketPeer.STATE_OPEN and client.get_ready_state() == WebSocketPeer.STATE_OPEN:
			break
		await process_frame
	assert(accepted and client.get_ready_state() == WebSocketPeer.STATE_OPEN and sender.get_ready_state() == WebSocketPeer.STATE_OPEN)
	var members: Array[Dictionary] = []
	for i in range(100):
		members.append({"playerId":"00000000-0000-4000-a000-%012d" % i,"name":"LongPlayerName123456","title":"Champion of the Eclipse","level":100,"x":12345.125+float(i),"y":-12345.125})
	var received: Array[Dictionary] = []
	gateway.persistent_world_event.connect(func(payload: Dictionary) -> void: received.append(payload))
	gateway.set("_world_peer", client)
	gateway.set("_world_ticket_sent", true)
	gateway.set("_world_server_id", "local-large-admission-test")
	gateway.set("_world_reconnect_enabled", false)
	var admission := {"type":"world_joined","interestWindows":true,"serverId":"local-large-admission-test","playerId":members[0]["playerId"],"revision":2,"eventSequence":30000,"worldState":{"eventSequence":30000},"members":members}
	var encoded := JSON.stringify(admission).to_utf8_buffer()
	assert(sender.send(encoded, WebSocketPeer.WRITE_MODE_TEXT) == OK)
	for frame in range(240):
		sender.poll()
		gateway.call("_process_persistent_world", 0.016)
		if not received.is_empty():
			break
		await process_frame
	assert(received.size() == 1)
	assert(received[0]["members"].size() == 100)
	assert(gateway.get("_world_ready") and gateway.get("_world_interest_windows"))
	assert(gateway.get("_world_last_event_sequence") == 30000)
	assert(sender.send_text(JSON.stringify({"type":"world_position_window","fromSequence":30001,"sequence":30010,"members":[members[1]]})) == OK)
	for frame in range(240):
		sender.poll()
		gateway.call("_process_persistent_world", 0.016)
		if received.size() == 2:
			break
		await process_frame
	assert(received.size() == 2 and gateway.get("_world_last_event_sequence") == 30010)
	print("LARGE_ADMISSION_CLIENT_PASS members=100 bytes=%d inbound_buffer=%d cursor=30010" % [encoded.size(),client.inbound_buffer_size])
	gateway.disconnect_from_persistent_world()
	sender.close()
	listener.stop()
	quit()
