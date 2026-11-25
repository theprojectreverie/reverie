extends SceneTree

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var packed := load("res://scenes/ui/components/summon_reveal_overlay.tscn") as PackedScene
	if packed == null:
		push_error("REVEAL_SCENE_LOAD_FAILED")
		quit(1)
		return
	var overlay := packed.instantiate() as SummonRevealOverlay
	root.add_child(overlay)
	await process_frame
	var failures: Array[String] = []
	for rarity in ["common", "epic", "legendary"]:
		var finished_count := [0]
		var callback := func() -> void: finished_count[0] += 1
		overlay.reveal_finished.connect(callback, CONNECT_ONE_SHOT)
		await overlay.play_reveal(rarity)
		await process_frame
		if finished_count[0] != 1:
			failures.append(rarity)
			print("REVEAL_SEQUENCE_FAILED rarity=", rarity, " finished_signal_count=", finished_count[0])
		else:
			print("REVEAL_SEQUENCE_COMPLETED rarity=", rarity)
		if not is_instance_valid(overlay) or not overlay.is_inside_tree():
			failures.append("overlay_removed")
			break
	overlay.queue_free()
	await process_frame
	if failures.is_empty():
		print("SUMMON_REVEAL_PLAYBACK_OK")
	else:
		push_error("SUMMON_REVEAL_PLAYBACK_FAILURES=" + ",".join(failures))
	quit(1 if not failures.is_empty() else 0)
