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
	visual.configure_character("lilith")
	var fx := visual.get_node_or_null("LilithSpectralEffects") as LilithSpectralEffects
	assert(fx != null, "LilithSpectralEffects scene must be integrated")
	var player := fx.get_node("AnimationPlayer") as AnimationPlayer
	assert(player != null, "Lilith FX must own AnimationPlayer")
	var states := {
		ActorVisual.S_IDLE: &"idle",
		ActorVisual.S_WALK: &"walk",
		ActorVisual.S_RUN: &"run",
		ActorVisual.S_INTERACT: &"interact",
		ActorVisual.S_ATTACK: &"attack",
		ActorVisual.S_CAST: &"cast",
		ActorVisual.S_DAMAGE: &"damage",
		ActorVisual.S_VICTORY: &"victory",
		ActorVisual.S_DEFEAT: &"defeat"
	}
	for state in states:
		var clip: StringName = states[state]
		assert(player.has_animation(clip), "Missing Lilith FX clip: %s" % clip)
		visual.play(state)
		await process_frame
		assert(player.current_animation == String(clip), "Lilith state %d failed to select %s (got %s)" % [state, clip, player.current_animation])
		assert(player.is_playing(), "Lilith FX clip did not start: %s" % clip)
	assert(fx.get_node("SpectralHalo/OuterArc") is Line2D, "Authored halo geometry missing")
	assert(fx.get_node("WispParticles") is CPUParticles2D, "Wisp emitter missing")
	assert(fx.get_node("AttackSparks") is CPUParticles2D, "Attack emitter missing")
	print("LILITH EDITOR-AUTHORED FX SMOKE: PASS (9/9 state clips and authored nodes)")
	visual.queue_free()
	await process_frame
	quit(0)
