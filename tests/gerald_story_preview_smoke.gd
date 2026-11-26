extends SceneTree

var failures: Array[String] = []
func _initialize() -> void:
	call_deferred("_run")

func check(ok: bool, label: String) -> void:
	print("CHECK ",label," = ",ok)
	if not ok:
		failures.append(label)

func click(button: Button) -> void:
	var pos := button.get_global_rect().get_center()
	var motion := InputEventMouseMotion.new()
	motion.position = pos
	root.push_input(motion)
	for pressed in [true,false]:
		var event := InputEventMouseButton.new()
		event.position = pos
		event.button_index = MOUSE_BUTTON_LEFT
		event.pressed = pressed
		root.push_input(event)
		await process_frame

func _run() -> void:
	if OS.get_environment("REVERIE_E2E_DISABLE_LOCAL_SAVE")!="1":
		quit(2)
		return
	root.size = Vector2i(1280,720)
	var scene = load("res://scenes/qa/gerald_story_preview.tscn").instantiate()
	root.add_child(scene)
	await process_frame
	await process_frame
	var state = root.get_node("GameState")
	var flags_before: Dictionary = state.flags.duplicate(true)
	var audio = root.get_node("AudioDirector")
	check(scene.menu.visible,"preview menu visible")
	for chapter in range(2):
		var btn: Button = scene.get_node("Menu/Content/"+("Before" if chapter==0 else "After"))
		await click(btn)
		await create_timer(1.6).timeout
		var id := "gerald_childhood" if chapter==0 else "gerald_tragedy"
		check(is_instance_valid(scene.active_story) and audio._current_track_id==id and audio._player.playing,"standalone chapter "+id)
		if not is_instance_valid(scene.active_story):
			quit(1)
			return
		var skip: Button = scene.active_story.get_node("SkipButton")
		check(not skip.get_global_rect().intersects(scene.return_button.get_global_rect()),"skip and return do not overlap")
		if chapter==0:
			await click(skip)
		else:
			await click(scene.return_button)
		await create_timer(1.1).timeout
		check(scene.menu.visible and not scene.running and audio.requested_music_track().is_empty(),"returns to menu cleanly")
	await click(scene.get_node("Menu/Content/Full"))
	var ids=["gerald_kael_after_battle","gerald_kael_after_the_fall","gerald_kael_farewell"]
	for i in range(3):
		await process_frame
		check(scene.dialogue.visible and scene.dialogue._dialogue_id==ids[i],"full story dialogue "+str(i))
		if not scene.dialogue.visible:
			quit(1)
			return
		var dialogue = scene.dialogue
		for j in range(8 if i==0 else 7):
			dialogue._finish_typing()
			dialogue._on_continue()
		dialogue._finish_typing()
		dialogue._choose(dialogue._node.choices[0])
		await create_timer(1.6).timeout
		if i<2:
			var id := "gerald_childhood" if i==0 else "gerald_tragedy"
			check(is_instance_valid(scene.active_story) and audio._current_track_id==id,"full story chapter "+str(i))
			if not is_instance_valid(scene.active_story):
				quit(1)
				return
			await click(scene.active_story.get_node("SkipButton"))
			await create_timer(1.1).timeout
	check(scene.menu.visible and not scene.running,"full story finishes")
	await click(scene.get_node("Menu/Content/Full"))
	await click(scene.return_button)
	await process_frame
	check(scene.menu.visible and not scene.running,"cancel during dialogue")
	check(state.flags==flags_before,"quest flags unchanged")
	print("PREVIEW_RESULT ",failures)
	quit(0 if failures.is_empty() else 1)