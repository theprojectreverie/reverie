extends SceneTree

func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var packed := load("res://scenes/characters/actor_visual.tscn") as PackedScene
	assert(packed != null, "ActorVisual scene must load")
	var visual := packed.instantiate() as ActorVisual
	assert(visual != null, "ActorVisual instance must be created")
	root.add_child(visual)
	await process_frame
	visual.configure_character("kael")
	var player := visual.get_node("AnimationPlayer") as AnimationPlayer
	var fx := visual.get_node("KaelCombatEffects")
	var fx_player := fx.get_node("AnimationPlayer") as AnimationPlayer
	assert(fx_player != null, "Kael VFX scene must own an AnimationPlayer")
	for fx_clip in [&"idle", &"walk", &"run", &"interact", &"attack", &"cast", &"damage", &"victory", &"defeat"]:
		assert(fx_player.has_animation(fx_clip), "Missing node-authored VFX animation: %s" % fx_clip)
	assert(player != null, "Authored AnimationPlayer must exist")
	var expected := {
		ActorVisual.S_IDLE: &"kael_idle_pose",
		ActorVisual.S_WALK: &"kael_walk_pose",
		ActorVisual.S_RUN: &"kael_run_pose",
		ActorVisual.S_INTERACT: &"kael_interact_pose",
		ActorVisual.S_ATTACK: &"kael_attack_pose",
		ActorVisual.S_CAST: &"kael_cast_pose",
		ActorVisual.S_DAMAGE: &"kael_damage_pose",
		ActorVisual.S_VICTORY: &"kael_victory_pose",
		ActorVisual.S_DEFEAT: &"kael_defeat_pose",

	}
	for state in expected:
		var clip: StringName = expected[state]
		assert(player.has_animation(clip), "Missing authored clip: %s" % clip)
		visual.play(state)
		assert(player.current_animation == String(clip), "State %d did not select %s (got %s)" % [state, clip, player.current_animation])
		assert(player.is_playing(), "AnimationPlayer did not start %s" % clip)
		await process_frame
	print("KAEL EDITOR-AUTHORED POSE SMOKE: PASS (9/9 states mapped to AnimationPlayer clips)")
	visual.queue_free()
	await process_frame
	quit(0)

