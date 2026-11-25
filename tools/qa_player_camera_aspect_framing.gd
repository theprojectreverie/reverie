extends SceneTree

func _initialize() -> void:
	call_deferred("_run")


func _check_aspect(view_size: Vector2i, expected_offset: float, label: String) -> bool:
	var viewport := SubViewport.new()
	viewport.size = view_size
	viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	root.add_child(viewport)
	var camera := PlayerCameraRig.new()
	viewport.add_child(camera)
	await process_frame
	for frame in range(12):
		camera.update_follow_offset(0.25, Vector2.ZERO, 0.0)
	var expected_x := PlayerCameraRig.PORTRAIT_HORIZONTAL_OFFSET if label == "portrait" else 0.0
	var expected_zoom := PlayerCameraRig.PORTRAIT_ZOOM_FACTOR if label == "portrait" else 1.0
	if absf(camera.offset.y - expected_offset) > 0.5 or absf(camera.offset.x - expected_x) > 0.5 or absf(camera.zoom.x - expected_zoom) > 0.01:
		push_error("%s camera framing mismatch: offset=%s zoom=%s" % [label, camera.offset, camera.zoom])
		viewport.queue_free()
		await process_frame
		return false
	print("CAMERA ASPECT: PASS (%s %s -> offset=%s zoom=%.3f)" % [label, view_size, camera.offset, camera.zoom.x])
	viewport.queue_free()
	await process_frame
	return true


func _run() -> void:
	var passed := true
	passed = await _check_aspect(Vector2i(1280, 720), 0.0, "landscape") and passed
	passed = await _check_aspect(Vector2i(480, 860), PlayerCameraRig.PORTRAIT_VERTICAL_OFFSET, "portrait") and passed
	passed = await _check_aspect(Vector2i(720, 720), 0.0, "square") and passed
	if not passed:
		quit(1)
		return
	print("PLAYER CAMERA ASPECT FRAMING QA: PASS")
	quit(0)
