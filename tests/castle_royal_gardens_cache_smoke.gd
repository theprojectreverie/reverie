extends SceneTree
const SCENE := "res://scenes/world/castle_royal_gardens.tscn"
func _initialize() -> void:
	call_deferred("_run")
func _run() -> void:
	var packed := load(SCENE) as PackedScene
	assert(packed != null, "Royal Gardens world failed to load")
	var world := packed.instantiate() as Node2D
	root.add_child(world)
	await process_frame
	await process_frame
	var expansion := world.get_node_or_null("ExpansionBuilder") as Node2D
	assert(expansion != null, "ExpansionBuilder missing")
	var placements := expansion.get_node_or_null("ApproachPlacements") as Node2D
	var interactables := expansion.get_node_or_null("ExpansionInteractables") as Node2D
	assert(placements != null, "ApproachPlacements missing")
	assert(interactables != null, "ExpansionInteractables missing")
	var marker := placements.get_node_or_null("GardenerSealCache") as Marker2D
	assert(marker != null, "GardenerSealCache marker missing")
	assert(str(marker.get_meta("collectible_id", "")) == "castle_royal_seal_cache", "Collectible identity mismatch")
	var cache: Node = null
	for child in interactables.get_children():
		if child.get("collectible_id") == "castle_royal_seal_cache":
			cache = child
			break
	assert(cache != null, "Runtime cache was not spawned from the authored marker")
	assert(str(cache.get("prop_kind")) == str(marker.get_meta("item_id")), "Cache item identity differs from marker")
	assert(str(cache.get("display_name")) == str(marker.get_meta("display_name")), "Cache display name differs from marker")
	assert(cache.get("collectible_rewards") == marker.get_meta("rewards"), "Cache rewards differ from authored marker")
	assert(str(cache.get("prompt")) == "Gather", "Collectible interaction prompt is not Gather")
	assert(cache.is_visible_in_tree(), "Unclaimed cache should be visible")
	var visual := cache.get_node_or_null("AuthoredVisual") as Node2D
	assert(visual != null, "Authored cache visual scene missing")
	var urn := visual.get_node_or_null("CacheUrn") as Sprite2D
	var glow := visual.get_node_or_null("SealGlow") as Sprite2D
	var shadow := visual.get_node_or_null("ContactShadow") as Sprite2D
	var animation_player := visual.get_node_or_null("AnimationPlayer") as AnimationPlayer
	assert(urn != null and urn.texture != null, "Cache urn artwork missing")
	assert(glow != null and glow.texture != null, "Royal seal glow artwork missing")
	assert(shadow != null and shadow.texture != null, "Cache contact shadow missing")
	assert(animation_player != null and animation_player.is_playing(), "Authored cache glow animation is not playing")
	assert(animation_player.current_animation == "glow_pulse", "Cache visual is not using its authored glow animation")
	var test_player := Node2D.new()
	test_player.add_to_group("player")
	world.add_child(test_player)
	test_player.global_position = cache.global_position
	cache.set("_player", test_player)
	for frame in range(20):
		await process_frame
	assert(visual.modulate.r > 1.0, "Authored cache visual does not respond to player proximity")
	test_player.queue_free()
	print("CASTLE CACHE RESULT: id=%s | rewards=%s | urn=%s | glow_animation=%s | proximity_response=%s" % [str(cache.get("collectible_id")), str(cache.get("collectible_rewards")), str(urn.texture.resource_path), animation_player.current_animation, str(visual.modulate.r > 1.0)])
	print("CASTLE ROYAL GARDENS CACHE: PASS (authored collectible marker, artwork and animation)")
	quit(0)
