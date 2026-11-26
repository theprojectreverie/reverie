extends SceneTree

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	if OS.get_environment("REVERIE_E2E_DISABLE_LOCAL_SAVE") != "1":
		quit(2)
		return
	var source: ActorFrameSource = SpriteFramesActorSource.from_playable("kael")
	assert(source.has_frames())
	var sheet: SpriteFrames = source.get("sprite_frames")
	var first_texture := source.frame(0,0,0)
	assert(first_texture != null)
	var before_memory := Performance.get_monitor(Performance.MEMORY_STATIC)
	var sources: Array[ActorFrameSource] = []
	var started := Time.get_ticks_usec()
	for i in range(100):
		var entry: ActorFrameSource = SpriteFramesActorSource.register_playable("kael")
		assert(entry.has_frames() and entry.validate_sheets().is_empty())
		assert(entry.get("sprite_frames") == sheet)
		assert(entry.frame(0,0,0) == first_texture)
		sources.append(entry)
	var elapsed := float(Time.get_ticks_usec()-started)/1000.0
	print("SHEET_REGISTRATION_BENCH "+JSON.stringify({"registrations":sources.size(),"ms":elapsed,"shared_texture":true,"shared_sheet":true,"memory_delta_mib":(Performance.get_monitor(Performance.MEMORY_STATIC)-before_memory)/1048576.0}))
	# Mutate only this isolated process's in-memory resource. Never save it.
	var count := [0]
	sheet.changed.connect(func() -> void: count[0] += 1)
	var speed := sheet.get_animation_speed(&"walk_0")
	sheet.set_animation_speed(&"walk_0", speed+1.0)
	var speed_signals: int = count[0]
	assert(not source.has_frames())
	sheet.set_animation_speed(&"walk_0", speed)
	assert(source.has_frames())
	var loop := sheet.get_animation_loop(&"walk_0")
	var prior: int = count[0]
	sheet.set_animation_loop(&"walk_0", not loop)
	var loop_signals: int = count[0]-prior
	assert(not source.has_frames())
	sheet.set_animation_loop(&"walk_0", loop)
	assert(source.has_frames())
	prior = count[0]
	var old := sheet.get_frame_texture(&"walk_0",0)
	sheet.set_frame(&"walk_0",0,null)
	var frame_signals: int = count[0]-prior
	assert(not source.has_frames())
	sheet.set_frame(&"walk_0",0,old)
	assert(source.has_frames())
	print("SHEET_MUTATION_SIGNALS "+JSON.stringify({"speed":speed_signals,"loop":loop_signals,"frame":frame_signals}))
	print("ACTOR_SHEET_REGISTRATION_PASS")
	quit()
