extends Node

func _ready() -> void:
	call_deferred("_run")

func _find_portrait(node: Node) -> PortraitView:
	if node is PortraitView:
		var p := node as PortraitView
		if p.portrait_texture != null and p.portrait_texture.resource_path.ends_with("/cassien_legendary_character.png"):
			return p
	for child in node.get_children():
		var result := _find_portrait(child)
		if result != null: return result
	return null

func _run() -> void:
	var db := get_node("/root/ContentDB")
	assert(db.validation_errors.is_empty(), str(db.validation_errors))
	var banner: Dictionary = db.get_banner("crimson_oath")
	assert(banner.get("featured") == ["cassien_mythic"])
	var rng := RandomNumberGenerator.new()
	rng.seed = 123
	var outcome := GachaService.pull(banner, rng, {"legendary": 0, "featured": int(banner.featured_pity) - 1, "epic_streak": 0}, 1)
	assert(outcome.results[0].character_id == "cassien_mythic" and outcome.results[0].rarity == "mythic" and outcome.results[0].featured)
	var paid := GachaService.pull(banner, rng, GachaService.empty_pity(), 1, 99)
	assert(paid.results[0].character_id == "cassien_mythic" and paid.results[0].paid_guaranteed)
	assert(db.get_character("cassien_mythic") != null)
	var gacha := (load("res://scenes/ui/gacha_screen.tscn") as PackedScene).instantiate() as GachaScreen
	add_child(gacha)
	for i in range(4): await get_tree().process_frame
	gacha._select_banner("crimson_oath")
	for i in range(4): await get_tree().process_frame
	assert(gacha._featured_id == "cassien_mythic")
	var portrait := _find_portrait(gacha)
	assert(portrait != null)
	assert(portrait.portrait_texture.get_size() == (load("res://assets/portraits/banners/cassien_legendary_character.png") as Texture2D).get_size())
	assert(gacha.get_node("SummoningChamberIllustration").texture.resource_path == "res://assets/portraits/banners/crimson_oath_background.png")
	assert(gacha._tabs.get_child_count() == gacha.active_banner_catalog().size())
	var backdrop := gacha.get_node("SummoningChamberIllustration") as TextureRect
	assert(is_equal_approx(backdrop.anchor_left, -0.20) and is_equal_approx(backdrop.anchor_right, 1.20))
	assert(is_equal_approx(backdrop.anchor_top, -0.20) and is_equal_approx(backdrop.anchor_bottom, 1.20))
	gacha._select_banner("eclipse_sovereign")
	for i in range(4): await get_tree().process_frame
	assert(is_equal_approx(backdrop.anchor_left, 0.0) and is_equal_approx(backdrop.anchor_right, 1.0))
	assert(is_equal_approx(backdrop.anchor_top, 0.0) and is_equal_approx(backdrop.anchor_bottom, 1.0))
	gacha._select_banner("crimson_oath")
	for i in range(4): await get_tree().process_frame
	assert(is_equal_approx(backdrop.anchor_left, -0.20))
	print("CRIMSON_OATH_ZOOM_PASS: 140% throne room zoom, reset on other banners, independent hero, Mythic featured")
	gacha.queue_free()
	await get_tree().process_frame
	get_tree().quit(0)
