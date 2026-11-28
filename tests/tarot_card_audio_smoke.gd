extends Node

func _ready() -> void:
	var reveal = load("res://scenes/ui/components/ravienna_summon.tscn").instantiate()
	add_child(reveal)
	await get_tree().process_frame
	var portrait := load("res://assets/portraits/banners/ravienna_character.png") as Texture2D
	var tarot := load("res://assets/ui/tarot/ravienna_the_empress.png") as Texture2D
	var bg := load("res://assets/portraits/banners/eclipse_sovereign_background.png") as Texture2D
	var speech := load("res://assets/audio/voice/ravienna/summon_greeting.wav") as AudioStream
	var expected := {"common":"ui_confirm_select", "rare":"ui_confirm_select", "epic":"magic_charge_1", "legendary":"legendary_reveal_1", "mythic":"mythic_reveal_1"}
	for rarity in expected:
		var premium: bool = rarity in ["legendary", "mythic"]
		reveal.configure(rarity, tarot if premium else portrait, "Ravienna", portrait, bg, speech if premium else null)
		reveal.play()
		await get_tree().create_timer(0.55).timeout
		var flip: AudioStreamPlayer = reveal.get_node("CardFlip")
		var hit: AudioStreamPlayer = reveal.get_node("CardReveal")
		assert(flip.playing and flip.stream != null)
		assert(not hit.playing)
		await get_tree().create_timer(0.35).timeout
		assert(hit.playing and hit.stream != null and hit.stream.resource_path.contains(expected[rarity]))
		assert(hit.bus == &"SFX")
		if premium:
			await get_tree().create_timer(1.3).timeout
			assert(reveal.get_node("CardDissolve").playing)
		reveal.cancel()
		for player_name in ["CardFlip", "CardReveal", "CardDissolve", "Voice"]:
			assert(not reveal.get_node(player_name).playing)
		assert(flip.stream == null and hit.stream == null)
		print("CARD_AUDIO_OK ", rarity)
		await get_tree().process_frame
	reveal.queue_free()
	await get_tree().process_frame
	await AudioDirector.drain_for_shutdown()
	print("ALL_FIVE_CARD_AUDIO_AND_SKIP_OK")
	get_tree().quit()