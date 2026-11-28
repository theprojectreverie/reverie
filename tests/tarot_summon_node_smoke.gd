extends Node

func _ready() -> void:
	var scene := load("res://scenes/ui/components/ravienna_summon.tscn") as PackedScene
	var reveal := scene.instantiate()
	add_child(reveal)
	await get_tree().process_frame
	var face := load("res://assets/ui/tarot/ravienna_the_empress.png") as Texture2D
	var portrait := load("res://assets/portraits/banners/ravienna_character.png") as Texture2D
	var bg := load("res://assets/portraits/banners/eclipse_sovereign_background.png") as Texture2D
	var voice := load("res://assets/audio/voice/ravienna/summon_greeting.wav") as AudioStream
	reveal.configure("mythic", face, "Ravienna", portrait, bg, voice)
	reveal.play()
	var ap := reveal.get_node("AnimationPlayer") as AnimationPlayer
	ap.seek(0.3, true)
	assert(reveal.get_node("Card/Face").modulate.a < 0.1)
	ap.seek(1.4, true)
	assert(reveal.get_node("Card/Face").modulate.a > 0.9)
	assert(reveal.get_node("Chamber").modulate.a < 0.1)
	ap.seek(4.0, true)
	assert(reveal.get_node("Chamber").modulate.a > 0.9)
	assert(reveal.get_node("Card").modulate.a < 0.1)
	assert(reveal.get_node("Voice").stream == voice)
	reveal.cancel()
	assert(not reveal.visible and not ap.is_playing())
	reveal.configure("common", portrait, "Ravienna", portrait, null, null)
	reveal.play()
	assert(ap.current_animation == "standard")
	assert(not reveal.get_node("Card/Aura").visible)
	reveal.cancel()
	reveal.queue_free()
	var overlay = load("res://scenes/ui/components/summon_reveal_overlay.tscn").instantiate()
	add_child(overlay)
	await get_tree().process_frame
	assert(overlay._tarot_base("revienna_mythic") == "ravienna")
	assert(overlay._tarot_base("lilith_legendary") == "lilith")
	Engine.time_scale = 12.0
	var did_play: bool = await overlay._play_tarot({"character_id":"ravienna_mythic"}, "mythic")
	assert(did_play and overlay.cinematic_count == 1)
	assert(overlay.ravienna_cinematic == null)
	assert(overlay._voice_in_cinematic)
	Engine.time_scale = 1.0
	get_tree().create_timer(0.15).timeout.connect(overlay.skip_all, CONNECT_ONE_SHOT)
	did_play = await overlay._play_tarot({"character_id":"ravienna_legendary"}, "legendary")
	assert(did_play and overlay.skipped and overlay.ravienna_cinematic == null)
	print("TAROT_SUMMON_NODE_SMOKE_OK")
	get_tree().quit()
