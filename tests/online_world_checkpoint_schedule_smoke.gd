extends SceneTree

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var packed: PackedScene = load("res://scenes/online/dedicated_world_server.tscn")
	var server: Node = packed.instantiate()
	server.set("transport_test_mode", true)
	root.add_child(server)
	# A save timer tick while the HTTP control channel is occupied must remain
	# pending; the next idle process frame will retry the checkpoint.
	server.set("_ready_for_heartbeat", true)
	server.set("_operation", "heartbeat")
	server.call("_save_world_state")
	assert(server.get("_checkpoint_due"))
	server.call("_try_save_world_state")
	assert(server.get("_checkpoint_due"))
	server.set("_operation", "")
	var queued: Array[Dictionary] = [{"event_id":"fixture","payload":{"type":"position","playerId":"fixture","x":2,"y":3}}]
	server.set("_event_queue", queued)
	server.call("_try_save_world_state")
	assert(server.get("_checkpoint_due"), "Uncommitted events must not advance a checkpoint")
	server.set("_event_queue", [] as Array[Dictionary])
	server.set("_event_request_active", true)
	server.call("_try_save_world_state")
	assert(server.get("_checkpoint_due"), "An in-flight batch must finish first")
	server.set("_event_request_active", false)
	server.set("_deferred_positions", {1:{"type":"position","playerId":"fixture","x":4,"y":5}})
	server.call("_try_save_world_state")
	assert(server.get("_checkpoint_due"), "Deferred movement must not be checkpointed as committed")
	server.set("_ready_for_heartbeat", false)
	server.queue_free()
	await process_frame
	print("WORLD_CHECKPOINT_SCHEDULE_SMOKE_PASS")
	quit()
