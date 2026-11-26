extends SceneTree
func _initialize():
	call_deferred("_run")
func _run():
	var packed=load("res://scenes/combat/presentation/boss_phase_cue.tscn")
	for i in range(6):
		var cue=packed.instantiate()
		root.add_child(cue)
		cue.play_cue("Test","Test","Ravienna",2,"Fractured Mind",Color.WHITE,"eclipse",0.2)
		if i%2==0:
			await cue.finished
		else:
			await create_timer(0.08).timeout
			cue.cancel_cue()
		var ref=weakref(cue)
		cue.queue_free()
		await process_frame
		await process_frame
		assert(ref.get_ref()==null)
	print("PHASE_CUE_TEARDOWN PASS")
	quit(0)
