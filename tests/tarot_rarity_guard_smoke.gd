extends Node

func _ready() -> void:
	var overlay: SummonRevealOverlay = load("res://scenes/ui/components/summon_reveal_overlay.tscn").instantiate()
	add_child(overlay)
	await get_tree().process_frame
	var checked := 0
	var adversarial_ids := {}
	for banner in ContentDB.banners.values():
		for rarity in ["common", "rare", "epic", "legendary", "mythic"]:
			for id in banner.get("pool", {}).get(rarity, []):
				assert(overlay._presentation_rarity({"character_id": id, "rarity": rarity}) == rarity)
				if rarity in ["rare", "epic"] and not adversarial_ids.has(id):
					adversarial_ids[id] = true
					assert(overlay._presentation_rarity({"character_id": id, "rarity": "mythic"}) == rarity)
				checked += 1
	print("CATALOG_RARITY_CHECKS=", checked)
	# Mixed batch: an Epic immediately after a real Mythic must be standard.
	var rolls := [
		{"character_id":"upgrade_ravienna_epic_v1","rarity":"epic"},
		{"character_id":"ravienna_mythic","rarity":"mythic"},
		{"character_id":"upgrade_gerald_epic_v1","rarity":"epic","fusions":[{"id":"gerald_mythic","name":"Gerald"}]},
		{"character_id":"upgrade_lilith_rare_v1","rarity":"rare"},
		{"character_id":"ravienna","rarity":"legendary"},
		{"character_id":"upgrade_cassien_epic_v1","rarity":"epic"}
	]
	var expected := ["standard","reveal","standard","standard","reveal","standard"]
	var observed: Array[String] = []
	var done := [false]
	overlay.reveal_finished.connect(func(): done[0] = true)
	var old_quality: int = GraphicsSettings.quality
	GraphicsSettings.quality = 2
	Engine.time_scale = 8.0
	overlay.play_batch(rolls)
	var seen: int = 0
	var last_node: Node = null
	var deadline := Time.get_ticks_msec() + 20000
	while not done[0] and Time.get_ticks_msec() < deadline:
		var node := overlay.ravienna_cinematic
		if is_instance_valid(node) and node != last_node:
			last_node = node
			var anim: AnimationPlayer = node.get_node("AnimationPlayer")
			if anim.is_playing():
				var mode := str(anim.current_animation)
				observed.append(mode)
				var idx := observed.size() - 1
				assert(mode == expected[idx])
				var back: Texture2D = node.get_node("Card/Back").texture
				assert(back.resource_path.ends_with("/" + str(rolls[idx].rarity) + ".png"))
				assert(overlay.cinematic_player.stream == null)
				if str(rolls[idx].rarity) == "epic":
					assert(node.get_node("Chamber/Portrait").texture != null)
					assert(node.get_node("Voice").stream == null)
					assert(not node.get_node("Chamber/Fog2").visible)
		if overlay.waiting_for_card and overlay.reveal_count > seen:
			seen = overlay.reveal_count
			assert(overlay.get_node("CardStage/Intro").text.begins_with(str(rolls[seen - 1].rarity).to_upper()))
			overlay.get_node("CardStage/NextButton").pressed.emit()
		await get_tree().process_frame
	Engine.time_scale = 1.0
	GraphicsSettings.quality = old_quality
	assert(done[0] and seen == rolls.size())
	assert(observed == expected)
	assert(overlay.cinematic_count == 2)
	print("MIXED_RARITY_BATCH_OK ", observed)
	overlay.queue_free()
	await get_tree().process_frame
	await AudioDirector.drain_for_shutdown()
	get_tree().quit()
