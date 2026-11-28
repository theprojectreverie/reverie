extends Node

func _ready() -> void:
	var reveal = load("res://scenes/ui/components/ravienna_summon.tscn").instantiate()
	var shade := ColorRect.new()
	shade.color = Color(0.015, 0.008, 0.035)
	add_child(shade)
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(reveal)
	await get_tree().process_frame
	var portrait := load("res://assets/portraits/banners/ravienna_character.png") as Texture2D
	var tarot := load("res://assets/ui/tarot/ravienna_the_empress.png") as Texture2D
	var bg := load("res://assets/portraits/banners/eclipse_sovereign_background.png") as Texture2D
	var speech := load("res://assets/audio/voice/ravienna/summon_greeting.wav") as AudioStream
	for rarity in ["common", "rare", "epic", "legendary", "mythic"]:
		var premium: bool = rarity in ["legendary", "mythic"]
		reveal.configure(rarity, tarot if premium else portrait, "Ravienna", portrait, bg, speech if premium else null)
		assert(reveal.get_node("Card/Back").texture != null)
		assert(not reveal.get_node("Card/BackPlaceholder").visible)
		assert(reveal.get_node("Card/Aura").visible == (rarity in ["epic", "legendary", "mythic"]))
		reveal.play()
		var ap: AnimationPlayer = reveal.get_node("AnimationPlayer")
		ap.pause()
		ap.seek(0.42, true)
		await capture("back_" + rarity)
		if premium:
			ap.seek(1.5, true)
			await capture("face_" + rarity)
		reveal.cancel()
	reveal.configure("mythic", tarot, "Ravienna", portrait, bg, speech)
	reveal.play()
	await get_tree().create_timer(2.2).timeout
	assert(reveal.get_node("Dissolve").emitting)
	await capture("dissolve_mythic")
	await get_tree().create_timer(1.65).timeout
	assert(reveal.get_node("Voice").playing)
	print("VOICE_ACTIVE length=", speech.get_length(), " position=", reveal.get_node("Voice").get_playback_position())
	await capture("cinematic_mythic")
	var portrait_node: Control = reveal.get_node("Chamber/Cinematic")
	var fixed_position := portrait_node.global_position
	var video: VideoStreamPlayer = portrait_node.get_node("Video")
	assert(portrait_node.visible and video.is_playing())
	assert(portrait_node.get_node("Embers").emitting)
	var playback_before := video.stream_position
	var smoke_before: Vector2 = portrait_node.get_node("SmokeLeft").position
	var hair_material := video.material as ShaderMaterial
	var phase_before: float = hair_material.get_shader_parameter("phase")
	await get_tree().create_timer(1.25).timeout
	assert(video.stream_position > playback_before)
	assert(portrait_node.global_position == fixed_position)
	assert(hair_material.get_shader_parameter("phase") > phase_before)
	await capture("cinematic_mythic_later")
	assert(portrait_node.get_node("SmokeLeft").position != smoke_before)
	print("TAKE2_VIDEO_CANDLE_AND_ENVIRONMENT_OK")
	await reveal.finished
	assert(not reveal.visible and not reveal.get_node("Voice").playing and not video.is_playing() and not portrait_node.get_node("Embers").emitting)
	print("ALL_FIVE_BACKS_AND_LIVE_CINEMATIC_OK")
	get_tree().quit()

func capture(key: String) -> void:
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	img.resize(1000, int(1000.0 * img.get_height() / img.get_width()), Image.INTERPOLATE_LANCZOS)
	img.save_jpg("user://tarot_final_%s.jpg" % key, 0.9)
